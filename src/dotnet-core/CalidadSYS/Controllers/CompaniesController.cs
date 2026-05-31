using CalidadSYS.ViewModels;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using QualityDMS.Domain.Entities;
using QualityDMS.Infrastructure.Persistence;

namespace CalidadSYS.Controllers;

/// <summary>
/// Panel multiempresa. Solo el SuperAdmin global gestiona empresas y puede ver
/// los documentos de cualquiera de ellas (bypassa el filtro de tenant).
/// </summary>
[Authorize(Roles = "SuperAdmin")]
public class CompaniesController(QualityDMSDbContext db) : Controller
{
    public async Task<IActionResult> Index(CancellationToken ct)
    {
        var companies = await db.Companies
            .OrderBy(c => c.Name)
            .Select(c => new CompanyRowViewModel
            {
                CompanyId   = c.CompanyId,
                Code        = c.Code,
                Name        = c.Name,
                TaxId       = c.TaxId,
                IsActive    = c.IsActive,
                DocumentCount = db.Documents.Count(d => d.CompanyId == c.CompanyId),
                UserCount     = db.Users.Count(u => u.CompanyId == c.CompanyId)
            })
            .ToListAsync(ct);

        ViewData["Title"] = "Empresas";
        return View(companies);
    }

    public async Task<IActionResult> Documents(int id, CancellationToken ct)
    {
        var company = await db.Companies.FirstOrDefaultAsync(c => c.CompanyId == id, ct);
        if (company is null) return NotFound();

        var docs = await db.Documents
            .Where(d => d.CompanyId == id)
            .OrderByDescending(d => d.CreatedAt)
            .Select(d => new CompanyDocumentViewModel
            {
                DocumentId   = d.DocumentId,
                Code         = d.Code,
                Title        = d.Title,
                Status       = d.Status,
                CategoryName = d.Category.Name,
                DepartmentName = d.Department.Name,
                CurrentVersion = d.Versions.Where(v => v.IsCurrent).Select(v => v.VersionNumber).FirstOrDefault()
            })
            .ToListAsync(ct);

        ViewData["Title"] = $"Documentos: {company.Name}";
        ViewBag.Company = company;
        return View(docs);
    }

    [HttpGet]
    public IActionResult Create()
    {
        ViewData["Title"] = "Nueva Empresa";
        return View(new CompanyRowViewModel());
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Create(CompanyRowViewModel vm, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(vm.Code) || string.IsNullOrWhiteSpace(vm.Name))
        {
            ModelState.AddModelError("", "Código y nombre son requeridos.");
            return View(vm);
        }
        if (await db.Companies.AnyAsync(c => c.Code == vm.Code, ct))
        {
            ModelState.AddModelError(nameof(vm.Code), "Ya existe una empresa con ese código.");
            return View(vm);
        }

        db.Companies.Add(new Company
        {
            Code = vm.Code.Trim(),
            Name = vm.Name.Trim(),
            TaxId = vm.TaxId?.Trim(),
            IsActive = true,
            CreatedBy = User.Identity?.Name ?? "superadmin"
        });
        await db.SaveChangesAsync(ct);

        TempData["Success"] = $"Empresa '{vm.Name}' creada.";
        return RedirectToAction(nameof(Index));
    }
}
