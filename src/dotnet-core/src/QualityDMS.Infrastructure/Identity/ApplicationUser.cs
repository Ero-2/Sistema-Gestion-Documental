using Microsoft.AspNetCore.Identity;

namespace QualityDMS.Infrastructure.Identity;

public class ApplicationUser : IdentityUser
{
    public string FirstName { get; set; } = string.Empty;
    public string LastName { get; set; } = string.Empty;
    /// <summary>Empresa del usuario. Null = SuperAdmin global (acceso a todas).</summary>
    public int? CompanyId { get; set; }
    public int? DepartmentId { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public string FullName => $"{FirstName} {LastName}".Trim();
}
