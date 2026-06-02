using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
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

        // SuperAdmin global: poder absoluto. Se le conceden todos los roles para que
        // pase cualquier [Authorize(Roles=...)], policy RequireRole y User.IsInRole()
        // de las vistas, sin tener que listar "SuperAdmin" en cada controller.
        var roleType = Options.ClaimsIdentity.RoleClaimType;
        if (identity.HasClaim(roleType, "SuperAdmin"))
        {
            var current = identity.FindAll(roleType).Select(c => c.Value).ToHashSet();
            var allRoles = await roleManager.Roles.Select(r => r.Name!).ToListAsync();
            foreach (var role in allRoles)
                if (!string.IsNullOrEmpty(role) && current.Add(role))
                    identity.AddClaim(new Claim(roleType, role));
        }
        return identity;
    }
}
