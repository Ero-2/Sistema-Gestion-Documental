using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using QualityDMS.Domain.Interfaces;

namespace CalidadSYS.Controllers;

/// <summary>
/// Búsqueda full-text consumiendo la API reutilizable de FastAPI/Mongo por HTTP
/// (sin tocar Mongo directamente). Acota a la empresa del usuario; el SuperAdmin
/// busca en todas.
/// </summary>
[Authorize]
public class SearchController(ISearchApiService searchApi, ICurrentUserService currentUser) : Controller
{
    public IActionResult Index()
    {
        ViewData["Title"] = "Búsqueda";
        ViewBag.IsSuperAdmin = currentUser.IsSuperAdmin;
        return View();
    }

    /// <summary>JSON para la búsqueda en vivo (type-ahead). Acota a la empresa del usuario.</summary>
    [HttpGet]
    public async Task<IActionResult> Api(string? q, CancellationToken ct)
    {
        int? companyFilter = currentUser.IsSuperAdmin ? null : currentUser.CompanyId;
        var results = await searchApi.SearchAsync(q, companyFilter, ct);

        return Json(results.Select(r => new
        {
            code = r.Code,
            title = r.Title,
            company = r.CompanyName,
            category = r.CategoryName,
            department = r.DepartmentName,
            version = r.Version,
            isActive = r.IsActive,
            indexed = r.ContentExtracted,
            fileName = r.FileName
        }));
    }
}
