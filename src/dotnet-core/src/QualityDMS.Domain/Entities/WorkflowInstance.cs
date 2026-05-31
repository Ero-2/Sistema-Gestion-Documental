using QualityDMS.Domain.Common;
using QualityDMS.Domain.Enums;

namespace QualityDMS.Domain.Entities;

public class WorkflowInstance : AuditableEntity
{
    public int WorkflowInstanceId { get; set; }
    public int DocumentId { get; set; }
    /// <summary>Versión (borrador) concreta que esta instancia somete a aprobación.</summary>
    public int? DocumentVersionId { get; set; }
    public int WorkflowTemplateId { get; set; }
    public int CurrentStepOrder { get; set; } = 1;
    public WorkflowStepStatus Status { get; set; } = WorkflowStepStatus.Pending;
    public DateTime? CompletedAt { get; set; }

    public Document Document { get; set; } = null!;
    public WorkflowTemplate WorkflowTemplate { get; set; } = null!;
    public ICollection<WorkflowAction> Actions { get; set; } = new List<WorkflowAction>();
}
