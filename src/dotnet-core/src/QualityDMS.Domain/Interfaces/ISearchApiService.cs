namespace QualityDMS.Domain.Interfaces;

/// <summary>
/// Cliente de la API de búsqueda reutilizable (FastAPI + MongoDB full-text).
/// .NET la consume por HTTP, sin acoplarse al driver de Mongo. La misma API la
/// usa PHP. Permite acotar por empresa (multiempresa).
/// </summary>
public interface ISearchApiService
{
    Task<IReadOnlyList<SearchResultItem>> SearchAsync(
        string? query, int? companyId, CancellationToken ct = default);
}

public class SearchResultItem
{
    public int PostgresId { get; set; }
    public int? CompanyId { get; set; }
    public string? CompanyName { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? CategoryName { get; set; }
    public string? DepartmentName { get; set; }
    public string? Version { get; set; }
    public bool IsActive { get; set; } = true;
    public string? FileUrl { get; set; }
    public string? FileName { get; set; }
    public string? Extension { get; set; }
    public bool ContentExtracted { get; set; }
}
