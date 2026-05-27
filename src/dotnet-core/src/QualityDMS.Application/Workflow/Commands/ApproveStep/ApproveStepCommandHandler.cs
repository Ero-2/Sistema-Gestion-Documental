using MediatR;
using QualityDMS.Application.Common.Exceptions;
using QualityDMS.Domain.Common;
using QualityDMS.Domain.Entities;
using QualityDMS.Domain.Enums;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Application.Workflow.Commands.ApproveStep;

public class ApproveStepCommandHandler(
    IDocumentRepository documentRepository,
    IWorkflowRepository workflowRepository,
    INotificationService notificationService,
    ICurrentUserService currentUser,
    IUnitOfWork uow,
    IPublicDmsWebhookService webhook,
    IPhpSyncService phpSync) : IRequestHandler<ApproveStepCommand, Result>
{
    public async Task<Result> Handle(ApproveStepCommand cmd, CancellationToken ct)
    {
        var document = await documentRepository.GetByIdAsync(cmd.DocumentId, ct)
            ?? throw new NotFoundException(nameof(Document), cmd.DocumentId);

        var instance = await workflowRepository.GetActiveInstanceByDocumentAsync(cmd.DocumentId, ct)
            ?? throw new NotFoundException(nameof(WorkflowInstance), cmd.DocumentId);

        var template = await workflowRepository.GetTemplateByIdAsync(instance.WorkflowTemplateId, ct)
            ?? throw new NotFoundException(nameof(WorkflowTemplate), instance.WorkflowTemplateId);

        var action = new WorkflowAction
        {
            WorkflowInstanceId = instance.WorkflowInstanceId,
            StepOrder = instance.CurrentStepOrder,
            ActionByUserId = currentUser.UserId,
            Action = WorkflowStepStatus.Approved,
            Comments = cmd.Comments,
            ActionDate = DateTime.UtcNow,
            CreatedBy = currentUser.UserId
        };
        await workflowRepository.AddActionAsync(action, ct);

        var steps = template.Steps.OrderBy(s => s.StepOrder).ToList();
        var nextStep = steps.FirstOrDefault(s => s.StepOrder > instance.CurrentStepOrder);
        var fullyApproved = nextStep is null;

        if (fullyApproved)
        {
            instance.Status = WorkflowStepStatus.Approved;
            instance.CompletedAt = DateTime.UtcNow;
            workflowRepository.UpdateInstance(instance);
            document.Approve(currentUser.UserId);
            documentRepository.Update(document);

            await notificationService.SendAsync(
                document.CreatedBy,
                NotificationType.DocumentApproved,
                $"Documento aprobado: {document.Code}",
                $"El documento '{document.Title}' ha sido aprobado.",
                document.DocumentId, ct);
        }
        else
        {
            instance.CurrentStepOrder = nextStep!.StepOrder;
            workflowRepository.UpdateInstance(instance);

            if (nextStep.AssignedUserId is not null)
            {
                await notificationService.SendAsync(
                    nextStep.AssignedUserId,
                    NotificationType.WorkflowStepAssigned,
                    $"Pendiente de aprobación: {document.Code}",
                    $"El documento '{document.Title}' requiere su aprobación (Paso {nextStep.StepOrder}).",
                    document.DocumentId, ct);
            }
        }

        await uow.SaveChangesAsync(ct);

        // Notify FastAPI (MongoDB) and PHP (PostgreSQL) after DB commit
        if (fullyApproved)
        {
            await webhook.NotifyDocumentApprovedAsync(document.DocumentId);
            await phpSync.TriggerSyncAsync(document.DocumentId);
        }

        return Result.Success();
    }
}
