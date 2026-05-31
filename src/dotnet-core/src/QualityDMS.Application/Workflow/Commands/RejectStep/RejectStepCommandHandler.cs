using MediatR;
using QualityDMS.Application.Common.Exceptions;
using QualityDMS.Domain.Common;
using QualityDMS.Domain.Entities;
using QualityDMS.Domain.Enums;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Application.Workflow.Commands.RejectStep;

public class RejectStepCommandHandler(
    IDocumentRepository documentRepository,
    IWorkflowRepository workflowRepository,
    INotificationService notificationService,
    ICurrentUserService currentUser,
    IUnitOfWork uow) : IRequestHandler<RejectStepCommand, Result>
{
    public async Task<Result> Handle(RejectStepCommand cmd, CancellationToken ct)
    {
        var document = await documentRepository.GetByIdWithVersionsAsync(cmd.DocumentId, ct)
            ?? throw new NotFoundException(nameof(Document), cmd.DocumentId);

        var instance = await workflowRepository.GetActiveInstanceByDocumentAsync(cmd.DocumentId, ct)
            ?? throw new NotFoundException(nameof(WorkflowInstance), cmd.DocumentId);

        var action = new WorkflowAction
        {
            WorkflowInstanceId = instance.WorkflowInstanceId,
            StepOrder = instance.CurrentStepOrder,
            ActionByUserId = currentUser.UserId,
            Action = WorkflowStepStatus.Rejected,
            Comments = cmd.Reason,
            ActionDate = DateTime.UtcNow,
            CreatedBy = currentUser.UserId
        };
        await workflowRepository.AddActionAsync(action, ct);

        instance.Status = WorkflowStepStatus.Rejected;
        instance.CompletedAt = DateTime.UtcNow;
        workflowRepository.UpdateInstance(instance);
        document.Reject(currentUser.UserId, cmd.Reason);
        documentRepository.Update(document);

        await notificationService.SendAsync(
            document.CreatedBy,
            NotificationType.DocumentRejected,
            $"Documento rechazado: {document.Code}",
            $"El documento '{document.Title}' fue rechazado. Motivo: {cmd.Reason}",
            document.DocumentId, ct);

        await uow.SaveChangesAsync(ct);
        return Result.Success();
    }
}
