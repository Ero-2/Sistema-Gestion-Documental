using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using QualityDMS.Domain.Enums;
using QualityDMS.Domain.Interfaces;
using QualityDMS.Infrastructure.Persistence;

namespace CalidadSYS.Controllers.Api;

[ApiController]
[Route("api/v1/[controller]")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme,
           Roles = "Admin,QualityManager")]
public class AdminController(
    QualityDMSDbContext db,
    IPhpSyncService phpSync,
    ILogger<AdminController> logger) : ControllerBase
{
    /// <summary>
    /// Reenvía todos los documentos aprobados de SQL Server a PHP/PostgreSQL.
    /// Solo sincroniza PHP — FastAPI/MongoDB no se toca (ya tiene los datos del seeder).
    /// Seguro de ejecutar múltiples veces: PHP usa ON CONFLICT DO UPDATE.
    /// </summary>
    [HttpPost("php-resync")]
    public async Task<IActionResult> PhpResync(
        [FromQuery] int maxParallel = 5,
        CancellationToken ct = default)
    {
        if (maxParallel < 1 || maxParallel > 20) return BadRequest("maxParallel debe estar entre 1 y 20.");

        var docs = await db.Documents
            .AsNoTracking()
            .Include(d => d.Company)
            .Include(d => d.Category)
            .Include(d => d.Department)
            .Include(d => d.Versions)
            .Where(d => d.Status == DocumentStatus.Approved)
            .ToListAsync(ct);

        logger.LogInformation("[PhpResync] Iniciando resync de {Count} documentos aprobados.", docs.Count);

        int ok = 0, fail = 0;
        var errors = new List<string>();

        var opts = new ParallelOptions { MaxDegreeOfParallelism = maxParallel, CancellationToken = ct };

        await Parallel.ForEachAsync(docs, opts, async (doc, innerCt) =>
        {
            var current = doc.Versions.FirstOrDefault(v => v.IsCurrent && v.Status == VersionStatus.Approved);
            if (current is null)
            {
                Interlocked.Increment(ref fail);
                return;
            }

            try
            {
                await phpSync.ApproveDocumentAsync(
                    doc.DocumentId,
                    doc.Code,
                    doc.Title,
                    doc.CategoryId,
                    doc.Category?.Name ?? "Unknown",
                    doc.DepartmentId,
                    doc.Department?.Name ?? "Unknown",
                    current.VersionNumber,
                    current.FilePath ?? string.Empty,
                    doc.EffectiveDate,
                    doc.ExpirationDate,
                    current.ApprovedAt,
                    doc.CompanyId,
                    doc.Company?.Name ?? string.Empty,
                    doc.NextReviewDate);

                Interlocked.Increment(ref ok);
            }
            catch (Exception ex)
            {
                Interlocked.Increment(ref fail);
                var msg = $"Doc {doc.DocumentId} ({doc.Code}): {ex.Message}";
                logger.LogWarning("[PhpResync] {Error}", msg);
                lock (errors)
                {
                    if (errors.Count < 20) errors.Add(msg);
                }
            }
        });

        logger.LogInformation("[PhpResync] Completado — {Ok} OK / {Fail} fallos de {Total}.", ok, fail, docs.Count);

        return Ok(new
        {
            total = docs.Count,
            synced = ok,
            failed = fail,
            sample_errors = errors
        });
    }
}
