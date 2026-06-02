using CalidadSYS.ViewModels;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Rendering;
using QualityDMS.Application.Documents.Commands.CreateDocument;
using QualityDMS.Application.Documents.Commands.ObsoleteDocument;
using QualityDMS.Application.Documents.Commands.UpdateDocument;
using QualityDMS.Application.Documents.Queries.GetDocumentById;
using QualityDMS.Application.Documents.Queries.GetDocuments;
using QualityDMS.Application.Workflow.Commands.SubmitDocument;
using QualityDMS.Domain.Interfaces;
using QualityDMS.Domain.Enums;
using QualityDMS.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace CalidadSYS.Controllers;

[Authorize]
public class DocumentsController(IMediator mediator, QualityDMSDbContext db, IFileStorageService fileStorage) : Controller
{
    public async Task<IActionResult> Index(DocumentFilterViewModel filter, CancellationToken ct)
    {
        var result = await mediator.Send(
            new GetDocumentsQuery(filter.CategoryId, filter.DepartmentId, filter.Status,
                filter.SearchTerm, filter.Page, filter.PageSize), ct);

        filter.Categories = await GetCategoriesSelectList();
        filter.Departments = await GetDepartmentsSelectList();

        ViewData["Title"] = "Documentos";
        ViewBag.Result = result;
        return View(filter);
    }

    public async Task<IActionResult> Details(int id, CancellationToken ct)
    {
        var doc = await mediator.Send(new GetDocumentByIdQuery(id), ct);
        if (doc is null) return NotFound();

        // CreatedBy guarda el Id (GUID) del usuario; resolverlo a nombre legible
        // para no mostrar el identificador crudo en la vista.
        ViewBag.CreatedByName = await ResolveUserNameAsync(doc.CreatedBy, ct);
        ViewData["Title"] = $"Documento: {doc.Code}";
        return View(doc);
    }

    /// <summary>Mapea un Id de usuario a "Nombre Apellido"; fallback a usuario/Id si no se encuentra.</summary>
    private async Task<string> ResolveUserNameAsync(string? userId, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(userId)) return "—";
        if (userId == "seed") return "Sistema";

        var u = await db.Users.IgnoreQueryFilters()
            .Where(x => x.Id == userId)
            .Select(x => new { x.FirstName, x.LastName, x.UserName })
            .FirstOrDefaultAsync(ct);
        if (u is null) return userId;

        var full = $"{u.FirstName} {u.LastName}".Trim();
        return full.Length > 0 ? full : (u.UserName ?? userId);
    }

    [Authorize(Roles = "DocumentManager,QualityManager,Admin")]
    public async Task<IActionResult> Create()
    {
        ViewData["Title"] = "Nuevo Documento";
        return View(new CreateDocumentViewModel
        {
            Categories = await GetCategoriesSelectList(),
            Departments = await GetDepartmentsSelectList(),
            WorkflowTemplates = await GetWorkflowTemplatesSelectList()
        });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(Roles = "DocumentManager,QualityManager,Admin")]
    public async Task<IActionResult> Create(CreateDocumentViewModel vm, CancellationToken ct)
    {
        if (!ModelState.IsValid)
        {
            vm.Categories = await GetCategoriesSelectList();
            vm.Departments = await GetDepartmentsSelectList();
            vm.WorkflowTemplates = await GetWorkflowTemplatesSelectList();
            return View(vm);
        }

        var cmd = new CreateDocumentCommand(
            vm.Code, vm.Title, vm.Description,
            vm.CategoryId, vm.DepartmentId, vm.WorkflowTemplateId,
            vm.NextReviewDate, vm.File!.FileName, vm.File.ContentType,
            vm.File.Length, vm.File.OpenReadStream());

        var result = await mediator.Send(cmd, ct);
        if (result.IsSuccess)
        {
            TempData["Success"] = "Documento creado exitosamente.";
            return RedirectToAction(nameof(Details), new { id = result.Value });
        }

        ModelState.AddModelError("", result.Error ?? "Error al crear el documento.");
        vm.Categories = await GetCategoriesSelectList();
        vm.Departments = await GetDepartmentsSelectList();
        vm.WorkflowTemplates = await GetWorkflowTemplatesSelectList();
        return View(vm);
    }

    [Authorize(Roles = "DocumentManager,QualityManager,Admin")]
    public async Task<IActionResult> Edit(int id, CancellationToken ct)
    {
        var doc = await mediator.Send(new GetDocumentByIdQuery(id), ct);
        if (doc is null) return NotFound();

        // Aprobado = iniciar nueva revisión (borrador X.1); la versión vigente X.0
        // queda intacta. Obsoleto sí se bloquea (documento dado de baja).
        if (doc.Status == DocumentStatus.Obsolete)
        {
            TempData["Error"] = "No se puede editar un documento obsoleto.";
            return RedirectToAction(nameof(Details), new { id });
        }

        ViewData["Title"] = doc.Status == DocumentStatus.Approved
            ? $"Nueva revisión: {doc.Code}"
            : $"Editar: {doc.Code}";
        return View(new EditDocumentViewModel
        {
            DocumentId = doc.DocumentId,
            Code = doc.Code,
            Title = doc.Title,
            Description = doc.Description,
            CategoryId = doc.CategoryId,
            DepartmentId = doc.DepartmentId,
            WorkflowTemplateId = doc.WorkflowTemplateId,
            NextReviewDate = doc.NextReviewDate,
            CurrentStatus = doc.Status,
            Categories = await GetCategoriesSelectList(),
            Departments = await GetDepartmentsSelectList(),
            WorkflowTemplates = await GetWorkflowTemplatesSelectList()
        });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(Roles = "DocumentManager,QualityManager,Admin")]
    public async Task<IActionResult> Edit(EditDocumentViewModel vm, CancellationToken ct)
    {
        if (!ModelState.IsValid)
        {
            vm.Categories = await GetCategoriesSelectList();
            vm.Departments = await GetDepartmentsSelectList();
            vm.WorkflowTemplates = await GetWorkflowTemplatesSelectList();
            return View(vm);
        }

        var cmd = new UpdateDocumentCommand(
            vm.DocumentId, vm.Title, vm.Description,
            vm.CategoryId, vm.DepartmentId, vm.WorkflowTemplateId,
            vm.NextReviewDate, vm.NewVersionNumber,
            vm.File?.FileName, vm.File?.ContentType, vm.File?.Length,
            vm.File?.OpenReadStream(), vm.ChangeLog);

        var result = await mediator.Send(cmd, ct);
        if (result.IsSuccess)
        {
            TempData["Success"] = "Documento actualizado.";
            return RedirectToAction(nameof(Details), new { id = vm.DocumentId });
        }

        ModelState.AddModelError("", result.Error ?? "Error al actualizar.");
        vm.Categories = await GetCategoriesSelectList();
        vm.Departments = await GetDepartmentsSelectList();
        vm.WorkflowTemplates = await GetWorkflowTemplatesSelectList();
        return View(vm);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Submit(int id, CancellationToken ct)
    {
        var result = await mediator.Send(new SubmitDocumentCommand(id), ct);
        TempData[result.IsSuccess ? "Success" : "Error"] =
            result.IsSuccess ? "Documento enviado a aprobación." : result.Error;
        return RedirectToAction(nameof(Details), new { id });
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [Authorize(Roles = "QualityManager,Admin")]
    public async Task<IActionResult> Obsolete(int id, CancellationToken ct)
    {
        var result = await mediator.Send(new ObsoleteDocumentCommand(id), ct);
        TempData[result.IsSuccess ? "Success" : "Error"] =
            result.IsSuccess ? "Documento marcado como obsoleto." : result.Error;
        return RedirectToAction(nameof(Details), new { id });
    }

    public async Task<IActionResult> Download(int versionId, CancellationToken ct)
    {
        var version = await db.DocumentVersions
            .FirstOrDefaultAsync(v => v.VersionId == versionId, ct);

        if (version is null) return NotFound();

        var stream = await fileStorage.DownloadAsync(version.FilePath, ct);
        var contentType = version.ContentType ?? "application/octet-stream";
        var fileName = version.FileName ?? $"version_{versionId}";
        return File(stream, contentType, fileName);
    }

    private async Task<IEnumerable<SelectListItem>> GetCategoriesSelectList() =>
        (await db.DocumentCategories.Where(c => c.IsActive).OrderBy(c => c.Name).ToListAsync())
        .Select(c => new SelectListItem(c.Name, c.CategoryId.ToString()));

    private async Task<IEnumerable<SelectListItem>> GetDepartmentsSelectList() =>
        (await db.Departments.Where(d => d.IsActive).OrderBy(d => d.Name).ToListAsync())
        .Select(d => new SelectListItem(d.Name, d.DepartmentId.ToString()));

    private async Task<IEnumerable<SelectListItem>> GetWorkflowTemplatesSelectList() =>
        (await db.WorkflowTemplates.Where(w => w.IsActive).OrderBy(w => w.Name).ToListAsync())
        .Select(w => new SelectListItem(w.Name, w.WorkflowTemplateId.ToString()));
}
