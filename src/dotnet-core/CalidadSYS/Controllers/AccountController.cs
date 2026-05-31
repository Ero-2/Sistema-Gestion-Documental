using CalidadSYS.ViewModels;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.EntityFrameworkCore;
using QualityDMS.Infrastructure.Identity;
using QualityDMS.Infrastructure.Persistence;

namespace CalidadSYS.Controllers;

public class AccountController(
    SignInManager<ApplicationUser> signInManager,
    UserManager<ApplicationUser> userManager,
    RoleManager<IdentityRole> roleManager,
    QualityDMSDbContext db) : Controller
{
    // AdminEmpresa puede crearse por registro; SuperAdmin solo por seeding.
    private static readonly string[] AllRoles =
        ["AdminEmpresa", "Admin", "QualityManager", "DocumentManager", "Approver", "Viewer"];

    private async Task<List<SelectListItem>> CompanyOptionsAsync() =>
        await db.Companies.Where(c => c.IsActive)
            .OrderBy(c => c.Name)
            .Select(c => new SelectListItem { Value = c.CompanyId.ToString(), Text = c.Name })
            .ToListAsync();

    // ── LOGIN ──────────────────────────────────────────────

    [HttpGet]
    [AllowAnonymous]
    public IActionResult Login(string? returnUrl = null)
    {
        if (User.Identity?.IsAuthenticated == true)
            return RedirectToAction("Index", "Dashboard");

        return View(new LoginViewModel { ReturnUrl = returnUrl });
    }

    [HttpPost]
    [AllowAnonymous]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Login(LoginViewModel vm)
    {
        if (!ModelState.IsValid) return View(vm);

        var result = await signInManager.PasswordSignInAsync(
            vm.Email, vm.Password, vm.RememberMe, lockoutOnFailure: true);

        if (result.Succeeded)
        {
            if (!string.IsNullOrEmpty(vm.ReturnUrl) && Url.IsLocalUrl(vm.ReturnUrl))
                return Redirect(vm.ReturnUrl);
            return RedirectToAction("Index", "Dashboard");
        }

        if (result.IsLockedOut)
        {
            ModelState.AddModelError("", "Cuenta bloqueada. Intente más tarde.");
            return View(vm);
        }

        ModelState.AddModelError("", "Correo o contraseña incorrectos.");
        return View(vm);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Logout()
    {
        await signInManager.SignOutAsync();
        return RedirectToAction("Login");
    }

    [AllowAnonymous]
    public IActionResult AccessDenied() => View();

    // ── REGISTER ───────────────────────────────────────────

    [HttpGet]
    [AllowAnonymous]
    public async Task<IActionResult> Register()
    {
        await EnsureRolesAsync();
        return View(new RegisterViewModel
        {
            AdminExists = await AdminExists(),
            Companies = await CompanyOptionsAsync()
        });
    }

    [HttpPost]
    [AllowAnonymous]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Register(RegisterViewModel vm)
    {
        await EnsureRolesAsync();
        vm.AdminExists = await AdminExists();
        vm.Companies = await CompanyOptionsAsync();

        // Bloquea rol Admin si ya existe uno
        if (vm.Role == "Admin" && vm.AdminExists)
        {
            ModelState.AddModelError(nameof(vm.Role),
                "Ya existe un administrador. Selecciona otro rol.");
            return View(vm);
        }

        // Todo usuario registrado pertenece a una empresa (aislamiento multiempresa).
        if (vm.CompanyId is null)
        {
            ModelState.AddModelError(nameof(vm.CompanyId), "Selecciona una empresa.");
            return View(vm);
        }

        if (!ModelState.IsValid) return View(vm);

        // Valida que el rol sea válido
        if (!AllRoles.Contains(vm.Role))
        {
            ModelState.AddModelError(nameof(vm.Role), "Rol inválido.");
            return View(vm);
        }

        var user = new ApplicationUser
        {
            UserName       = vm.Email,
            Email          = vm.Email,
            FirstName      = vm.FirstName.Trim(),
            LastName       = vm.LastName.Trim(),
            CompanyId      = vm.CompanyId,
            IsActive       = true,
            EmailConfirmed = true
        };

        var result = await userManager.CreateAsync(user, vm.Password);
        if (!result.Succeeded)
        {
            foreach (var err in result.Errors)
                ModelState.AddModelError("", err.Description);
            return View(vm);
        }

        await userManager.AddToRoleAsync(user, vm.Role);
        await signInManager.SignInAsync(user, isPersistent: false);

        TempData["Success"] = $"Bienvenido {user.FullName} — rol: {vm.Role}";
        return RedirectToAction("Index", "Dashboard");
    }

    // ── HELPERS ────────────────────────────────────────────

    private async Task EnsureRolesAsync()
    {
        foreach (var role in AllRoles)
            if (!await roleManager.RoleExistsAsync(role))
                await roleManager.CreateAsync(new IdentityRole(role));
    }

    private async Task<bool> AdminExists() =>
        (await userManager.GetUsersInRoleAsync("Admin")).Count > 0;
}
