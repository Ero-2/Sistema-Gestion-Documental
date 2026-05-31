using System.ComponentModel.DataAnnotations;
using QualityDMS.Domain.Enums;

namespace CalidadSYS.ViewModels;

public class CompanyRowViewModel
{
    public int CompanyId { get; set; }

    [Required(ErrorMessage = "El código es requerido")]
    [StringLength(20)]
    [Display(Name = "Código")]
    public string Code { get; set; } = string.Empty;

    [Required(ErrorMessage = "El nombre es requerido")]
    [StringLength(200)]
    [Display(Name = "Nombre")]
    public string Name { get; set; } = string.Empty;

    [StringLength(50)]
    [Display(Name = "RFC / Tax ID")]
    public string? TaxId { get; set; }

    public bool IsActive { get; set; } = true;
    public int DocumentCount { get; set; }
    public int UserCount { get; set; }
}

public class CompanyDocumentViewModel
{
    public int DocumentId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public DocumentStatus Status { get; set; }
    public string StatusName => Status.ToString();
    public string CategoryName { get; set; } = string.Empty;
    public string DepartmentName { get; set; } = string.Empty;
    public string? CurrentVersion { get; set; }
}
