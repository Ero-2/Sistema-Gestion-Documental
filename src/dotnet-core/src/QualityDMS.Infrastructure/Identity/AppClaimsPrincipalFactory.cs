using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;
using QualityDMS.Infrastructure.Services;

namespace QualityDMS.Infrastructure.Identity;

/// <summary>
/// Inyecta el claim de empresa (CompanyId) en el principal al iniciar sesión,
/// para que el aislamiento multiempresa (query filters) funcione sin golpear la BD.
/// Usuarios sin empresa (SuperAdmin global) no llevan el claim.
/// </summary>
public class AppClaimsPrincipalFactory(
    UserManager<ApplicationUser> userManager,
    RoleManager<IdentityRole> roleManager,
    IOptions<IdentityOptions> options)
    : UserClaimsPrincipalFactory<ApplicationUser, IdentityRole>(userManager, roleManager, options)
{
    protected override async Task<ClaimsIdentity> GenerateClaimsAsync(ApplicationUser user)
    {
        var identity = await base.GenerateClaimsAsync(user);
        if (user.CompanyId is int companyId)
            identity.AddClaim(new Claim(CurrentUserService.CompanyClaim, companyId.ToString()));
        return identity;
    }
}
