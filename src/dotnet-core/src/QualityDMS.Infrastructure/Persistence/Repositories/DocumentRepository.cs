using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using QualityDMS.Domain.Entities;
using QualityDMS.Domain.Enums;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Infrastructure.Persistence.Repositories;


public class DocumentRepository(
    QualityDMSDbContext ctx,
    IDocumentSearchService searchService,
    ILogger<DocumentRepository> logger) : IDocumentRepository
{
    public async Task<Document?> GetByIdAsync(int id, CancellationToken ct = default)
        => await ctx.Documents
            .Include(d => d.Category)
            .Include(d => d.Department)
            .FirstOrDefaultAsync(d => d.DocumentId == id, ct);

    public async Task<Document?> GetByIdWithVersionsAsync(int id, CancellationToken ct = default)
        => await ctx.Documents
            .Include(d => d.Company)
            .Include(d => d.Category)
            .Include(d => d.Department)
            .Include(d => d.Versions)
            .FirstOrDefaultAsync(d => d.DocumentId == id, ct);

    public async Task<IEnumerable<Document>> GetAllAsync(CancellationToken ct = default)
        => await ctx.Documents
            .AsNoTracking()
            .Include(d => d.Category)
            .Include(d => d.Department)
            .Include(d => d.Versions)
            .ToListAsync(ct);

    public async Task<(IEnumerable<Document> Items, int TotalCount)> GetPagedAsync(
        int? categoryId, int? departmentId, DocumentStatus? status,
        string? searchTerm, int page, int pageSize, CancellationToken ct = default)
    {
        var query = ctx.Documents
            .AsNoTracking()
            .Include(d => d.Company)
            .Include(d => d.Category)
            .Include(d => d.Department)
            .Include(d => d.Versions)
            .AsQueryable();

        if (categoryId.HasValue) query = query.Where(d => d.CategoryId == categoryId.Value);
        if (departmentId.HasValue) query = query.Where(d => d.DepartmentId == departmentId.Value);
        if (status.HasValue) query = query.Where(d => d.Status == status.Value);

        if (!string.IsNullOrWhiteSpace(searchTerm))
        {
            List<int>? mongoIds = null;
            try
            {
                mongoIds = (await searchService.SearchDocumentIdsAsync(searchTerm, ct)).ToList();
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "MongoDB search unavailable for term '{Term}', falling back to SQL LIKE", searchTerm);
            }

            if (mongoIds is not null)
            {
                if (mongoIds.Count == 0)
                    return ([], 0);

                // Fetch from SQL filtered by Mongo IDs, then reorder by Mongo relevance rank
                var docs = await query.Where(d => mongoIds.Contains(d.DocumentId)).ToListAsync(ct);
                var ordered = mongoIds
                    .Select(id => docs.FirstOrDefault(d => d.DocumentId == id))
                    .Where(d => d is not null)
                    .Cast<Document>()
                    .ToList();
                return (ordered.Skip((page - 1) * pageSize).Take(pageSize), ordered.Count);
            }

            // MongoDB unavailable — SQL LIKE fallback
            query = query.Where(d => d.Code.Contains(searchTerm) || d.Title.Contains(searchTerm));
        }

        var total = await query.CountAsync(ct);
        var items = await query
            .OrderByDescending(d => d.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        return (items, total);
    }

    public async Task<IEnumerable<Document>> GetExpiringAsync(int daysAhead, CancellationToken ct = default)
    {
        var threshold = DateTime.UtcNow.AddDays(daysAhead);
        return await ctx.Documents
            .AsNoTracking()
            .Include(d => d.Category)
            .Include(d => d.Department)
            .Where(d => d.Status == DocumentStatus.Approved
                && d.NextReviewDate.HasValue
                && d.NextReviewDate <= threshold)
            .OrderBy(d => d.NextReviewDate)
            .ToListAsync(ct);
    }

    public async Task<bool> CodeExistsAsync(string code, int? excludeId = null, CancellationToken ct = default)
    {
        var query = ctx.Documents.Where(d => d.Code == code);
        if (excludeId.HasValue) query = query.Where(d => d.DocumentId != excludeId.Value);
        return await query.AnyAsync(ct);
    }

    public async Task AddAsync(Document document, CancellationToken ct = default)
        => await ctx.Documents.AddAsync(document, ct);

    public void Update(Document document) => ctx.Documents.Update(document);

    public void Delete(Document document) => ctx.Documents.Remove(document);
}
