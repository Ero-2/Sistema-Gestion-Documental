using Microsoft.AspNetCore.Http;
using QualityDMS.Domain.Interfaces;
using System.Security.Claims;

namespace QualityDMS.Infrastructure.Services;

public class CurrentUserService(IHttpContextAccessor httpContextAccessor) : ICurrentUserService
{
    public string UserId => httpContextAccessor.HttpContext?.User?.FindFirstValue(ClaimTypes.NameIdentifier) ?? string.Empty;
    public string UserName => httpContextAccessor.HttpContext?.User?.FindFirstValue(ClaimTypes.Name) ?? string.Empty;
    public bool IsAuthenticated => httpContextAccessor.HttpContext?.User?.Identity?.IsAuthenticated ?? false;
    public IEnumerable<string> Roles =>
        httpContextAccessor.HttpContext?.User?.FindAll(ClaimTypes.Role).Select(c => c.Value) ?? [];

    public const string CompanyClaim = "CompanyId";

    public int? CompanyId
    {
        get
        {
            var raw = httpContextAccessor.HttpContext?.User?.FindFirstValue(CompanyClaim);
            return int.TryParse(raw, out var id) ? id : null;
        }
    }

    public bool IsSuperAdmin =>
        httpContextAccessor.HttpContext?.User?.IsInRole("SuperAdmin") ?? false;
}
