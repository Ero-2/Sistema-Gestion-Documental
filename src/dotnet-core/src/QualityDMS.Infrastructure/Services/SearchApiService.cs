using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Infrastructure.Services;

/// <summary>
/// Consume la API de búsqueda de FastAPI (/search/documents) por HTTP con X-API-Key.
/// .NET NO toca Mongo directamente: usa la misma API reutilizable que PHP.
/// </summary>
public class SearchApiService(HttpClient httpClient, ILogger<SearchApiService> logger) : ISearchApiService
{
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    public async Task<IReadOnlyList<SearchResultItem>> SearchAsync(
        string? query, int? companyId, CancellationToken ct = default)
    {
        try
        {
            var url = "/search/documents?limit=300";
            if (!string.IsNullOrWhiteSpace(query) && query.Trim().Length >= 2)
                url += "&q=" + Uri.EscapeDataString(query.Trim());
            if (companyId is int cid)
                url += "&company_id=" + cid;

            var response = await httpClient.GetAsync(url, ct);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogWarning("Search API [{Status}] q='{Query}'", response.StatusCode, query);
                return [];
            }

            var body = await response.Content.ReadAsStringAsync(ct);
            var parsed = JsonSerializer.Deserialize<SearchResponseDto>(body, JsonOpts);
            return (parsed?.Documents ?? [])
                .Select(d => new SearchResultItem
                {
                    PostgresId       = int.TryParse(d.PostgresId, out var n) ? n : 0,
                    CompanyId        = d.CompanyId,
                    CompanyName      = d.CompanyName,
                    Code             = d.Code ?? string.Empty,
                    Title            = d.Title ?? string.Empty,
                    CategoryName     = d.CategoryName,
                    DepartmentName   = d.DepartmentName,
                    Version          = d.Version,
                    IsActive         = d.IsActive ?? true,
                    FileUrl          = d.FileUrl,
                    FileName         = d.FileName,
                    Extension        = d.Extension,
                    ContentExtracted = d.ContentExtracted ?? false,
                })
                .ToList();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Search API unavailable for q='{Query}'", query);
            return [];
        }
    }

    private sealed class SearchResponseDto
    {
        [JsonPropertyName("documents")]
        public List<SearchResultDto> Documents { get; set; } = [];
    }

    private sealed class SearchResultDto
    {
        [JsonPropertyName("postgres_id")]     public string? PostgresId { get; set; }
        [JsonPropertyName("company_id")]      public int? CompanyId { get; set; }
        [JsonPropertyName("company_name")]    public string? CompanyName { get; set; }
        [JsonPropertyName("code")]            public string? Code { get; set; }
        [JsonPropertyName("title")]           public string? Title { get; set; }
        [JsonPropertyName("category_name")]   public string? CategoryName { get; set; }
        [JsonPropertyName("department_name")] public string? DepartmentName { get; set; }
        [JsonPropertyName("version")]         public string? Version { get; set; }
        [JsonPropertyName("is_active")]       public bool? IsActive { get; set; }
        [JsonPropertyName("file_url")]        public string? FileUrl { get; set; }
        [JsonPropertyName("file_name")]       public string? FileName { get; set; }
        [JsonPropertyName("extension")]       public string? Extension { get; set; }
        [JsonPropertyName("content_extracted")] public bool? ContentExtracted { get; set; }
    }
}
