using QualityDMS.Domain.Common;

namespace QualityDMS.Domain.Entities;

public class WorkflowTemplate : AuditableEntity
{
    public int WorkflowTemplateId { get; set; }
    public int CompanyId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool IsActive { get; set; } = true;

    public Company Company { get; set; } = null!;
    public ICollection<WorkflowStep> Steps { get; set; } = new List<WorkflowStep>();
    public ICollection<Document> Documents { get; set; } = new List<Document>();
}
