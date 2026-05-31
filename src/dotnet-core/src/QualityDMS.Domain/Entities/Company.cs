using QualityDMS.Domain.Common;

namespace QualityDMS.Domain.Entities;

/// <summary>
/// Empresa (tenant). Raíz del aislamiento multiempresa: usuarios, documentos,
/// departamentos, categorías y flujos pertenecen a una empresa. El SuperAdmin
/// global (CompanyId nulo en el usuario) no está atado a ninguna.
/// </summary>
public class Company : AuditableEntity
{
    public int CompanyId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? TaxId { get; set; }
    public bool IsActive { get; set; } = true;

    public ICollection<Document> Documents { get; set; } = new List<Document>();
    public ICollection<Department> Departments { get; set; } = new List<Department>();
    public ICollection<DocumentCategory> Categories { get; set; } = new List<DocumentCategory>();
    public ICollection<WorkflowTemplate> WorkflowTemplates { get; set; } = new List<WorkflowTemplate>();
}
