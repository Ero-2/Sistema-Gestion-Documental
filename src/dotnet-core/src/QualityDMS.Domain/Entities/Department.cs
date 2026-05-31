using QualityDMS.Domain.Common;

namespace QualityDMS.Domain.Entities;

public class Department : AuditableEntity
{
    public int DepartmentId { get; set; }
    public int CompanyId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? ManagerName { get; set; }
    public bool IsActive { get; set; } = true;

    public Company Company { get; set; } = null!;
    public ICollection<Document> Documents { get; set; } = new List<Document>();
}
