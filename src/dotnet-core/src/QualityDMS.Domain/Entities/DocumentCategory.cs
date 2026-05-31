using QualityDMS.Domain.Common;

namespace QualityDMS.Domain.Entities;

public class DocumentCategory : AuditableEntity
{
    public int CategoryId { get; set; }
    public int CompanyId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int? ParentCategoryId { get; set; }
    public bool IsActive { get; set; } = true;

    public Company Company { get; set; } = null!;
    public DocumentCategory? ParentCategory { get; set; }
    public ICollection<DocumentCategory> SubCategories { get; set; } = new List<DocumentCategory>();
    public ICollection<Document> Documents { get; set; } = new List<Document>();
}
