using MediatR;
using QualityDMS.Application.Common.Exceptions;
using QualityDMS.Domain.Common;
using QualityDMS.Domain.Entities;
using QualityDMS.Domain.Enums;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Application.Workflow.Commands.SubmitDocument;

public class SubmitDocumentCommandHandler(
    IDocumentRepository documentRepository,
    IWorkflowRepository workflowRepository,
    INotificationService notificationService,
    ICurrentUserService currentUser,
    IUnitOfWork uow) : IRequestHandler<SubmitDocumentCommand, Result>
{
    public async Task<Result> Handle(SubmitDocumentCommand cmd, CancellationToken ct)
    {
        var document = await documentRepository.GetByIdWithVersionsAsync(cmd.DocumentId, ct)
            ?? throw new NotFoundException(nameof(Document), cmd.DocumentId);

        if (document.WorkflowTemplateId is null)
            return Result.Failure("El documento no tiene plantilla de workflow asignada.");

        var template = await workflowRepository.GetTemplateByIdAsync(document.WorkflowTemplateId.Value, ct)
            ?? throw new NotFoundException(nameof(WorkflowTemplate), document.WorkflowTemplateId.Value);

        var submitted = document.SubmitForApproval();
        document.UpdatedBy = currentUser.UserId;

        var instance = new WorkflowInstance
        {
            DocumentId = document.DocumentId,
            DocumentVersionId = submitted.VersionId,
            WorkflowTemplateId = template.WorkflowTemplateId,
            CurrentStepOrder = 1,
            Status = WorkflowStepStatus.InProgress,
            CreatedBy = currentUser.UserId
        };

        await workflowRepository.AddInstanceAsync(instance, ct);
        documentRepository.Update(document);
        await uow.SaveChangesAsync(ct);

        if (!template.Steps.Any())
            return Result.Failure("La plantilla de workflow no tiene pasos configurados.");

        var firstStep = template.Steps.OrderBy(s => s.StepOrder).First();
        if (firstStep.AssignedUserId is not null)
        {
            await notificationService.SendAsync(
                firstStep.AssignedUserId,
                NotificationType.DocumentPendingApproval,
                $"Documento pendiente: {document.Code}",
                $"El documento '{document.Title}' requiere su aprobación.",
                document.DocumentId, ct);
        }
        else if (firstStep.AssignedRoleName is not null)
        {
            await notificationService.SendToRoleAsync(
                firstStep.AssignedRoleName,
                NotificationType.DocumentPendingApproval,
                $"Documento pendiente: {document.Code}",
                $"El documento '{document.Title}' requiere aprobación.",
                document.DocumentId, ct);
        }

        return Result.Success();
    }
}
