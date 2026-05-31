namespace QualityDMS.Domain.Interfaces;

public interface ICurrentUserService
{
    string UserId { get; }
    string UserName { get; }
    bool IsAuthenticated { get; }
    IEnumerable<string> Roles { get; }

    /// <summary>Empresa del usuario actual. Null = SuperAdmin global (sin tenant).</summary>
    int? CompanyId { get; }
    /// <summary>True si el usuario es SuperAdmin global (ve todas las empresas).</summary>
    bool IsSuperAdmin { get; }
}
