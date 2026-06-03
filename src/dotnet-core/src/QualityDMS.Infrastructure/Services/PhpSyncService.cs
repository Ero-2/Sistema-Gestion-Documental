using System.Net.Http.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Infrastructure.Services;

public class PhpSyncService(
    HttpClient httpClient,
    IConfiguration config,
    ILogger<PhpSyncService> logger) : IPhpSyncService
{
    private const int MaxRetries = 3;
    private const int RetryDelayMs = 1000;

    // ── Documents API (PostgreSQL via PHP) ────────────────────────────────

    public async Task ApproveDocumentAsync(int documentId, string code, string title,
        int categoryId, string categoryName, int departmentId, string departmentName,
        string version, string fileUrl, DateTime? effectiveDate, DateTime? expirationDate,
        DateTime? approvedAt = null, int companyId = 0, string companyName = "",
        DateTime? nextReviewDate = null)
    {
        var payload = new
        {
            document_id = documentId,
            code = code,
            title = title,
            category_id = categoryId,
            category_name = categoryName,
            department_id = departmentId,
            department_name = departmentName,
            version = version,
            file_url = fileUrl,
            effective_date = effectiveDate,
            expiration_date = expirationDate,
            approved_at = approvedAt,
            company_id = companyId,
            company_name = companyName,
            next_review_date = nextReviewDate
        };

        await SendWithRetryAsync("api/events.php?action=approve", payload,
            $"Doc {documentId} aprobado en PHP");
    }

    public async Task UpdateDocumentAsync(int documentId, bool isActive,
        DateTime? effectiveDate, DateTime? expirationDate, string reason = null,
        DateTime? nextReviewDate = null)
    {
        var payload = new
        {
            document_id = documentId,
            is_active = isActive,
            effective_date = effectiveDate,
            expiration_date = expirationDate,
            reason = reason,
            next_review_date = nextReviewDate
        };

        await SendWithRetryAsync("api/events.php?action=update", payload,
            $"Doc {documentId} actualizado en PHP");
    }

    public async Task VersionDocumentAsync(int documentId, string version, string fileUrl)
    {
        var payload = new
        {
            document_id = documentId,
            version = version,
            file_url = fileUrl,
            created_at = DateTime.UtcNow
        };

        await SendWithRetryAsync("api/events.php?action=version", payload,
            $"Doc {documentId} v{version} en PHP");
    }

    public async Task ObsoleteDocumentAsync(int documentId, string obsoleteReason)
    {
        var payload = new
        {
            document_id = documentId,
            obsolete_reason = obsoleteReason,
            effective_at = DateTime.UtcNow
        };

        await SendWithRetryAsync("api/events.php?action=obsolete", payload,
            $"Doc {documentId} obsoleto en PHP");
    }

    // ── Metadata API (MongoDB via FastAPI) ────────────────────────────────────

    public async Task RegisterMetadataAsync(int postgresId, string code, string title,
        string categoryName, string departmentName, string fileUrl, string version)
    {
        var fastapiUrl = config["PublicDms:WebhookUrl"] ?? "http://dms_fastapi:8000";
        var fastapiKey = config["PublicDms:ApiKey"] ?? "";

        var payload = new
        {
            postgres_id = postgresId,
            code = code,
            title = title,
            category_name = categoryName,
            department_name = departmentName,
            file_url = fileUrl,
            version = version
        };

        await SendMetadataWithRetryAsync($"{fastapiUrl}/api/metadata/register", payload,
            fastapiKey, $"Metadata registrado para doc {postgresId}");
    }

    public async Task UpdateMetadataAsync(int postgresId, Dictionary<string, object> updates)
    {
        var fastapiUrl = config["PublicDms:WebhookUrl"] ?? "http://dms_fastapi:8000";
        var fastapiKey = config["PublicDms:ApiKey"] ?? "";

        var payload = new
        {
            postgres_id = postgresId,
            updates = updates,
            updated_at = DateTime.UtcNow
        };

        await SendMetadataWithRetryAsync($"{fastapiUrl}/api/metadata/update", payload,
            fastapiKey, $"Metadata actualizado para doc {postgresId}");
    }

    public async Task LogMetadataHistoryAsync(int postgresId, string action, Dictionary<string, object> details)
    {
        var fastapiUrl = config["PublicDms:WebhookUrl"] ?? "http://dms_fastapi:8000";
        var fastapiKey = config["PublicDms:ApiKey"] ?? "";

        var payload = new
        {
            postgres_id = postgresId,
            action = action,
            details = details,
            timestamp = DateTime.UtcNow
        };

        await SendMetadataWithRetryAsync($"{fastapiUrl}/api/metadata/history", payload,
            fastapiKey, $"Evento '{action}' registrado para doc {postgresId}");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private async Task SendWithRetryAsync(string endpoint, object payload, string logMessage)
    {
        for (int attempt = 1; attempt <= MaxRetries; attempt++)
        {
            try
            {
                var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
                {
                    Content = JsonContent.Create(payload)
                };

                var response = await httpClient.SendAsync(request);

                if (response.IsSuccessStatusCode)
                {
                    logger.LogInformation("✓ {Message}", logMessage);
                    return;
                }

                if ((int)response.StatusCode < 500)
                {
                    // 4xx = error definitivo del cliente, no reintentable
                    throw new HttpRequestException(
                        $"PHP API [{response.StatusCode}] {logMessage}");
                }

                logger.LogWarning("✗ Attempt {Attempt}/{MaxRetries} failed [{Status}]: {Message}",
                    attempt, MaxRetries, response.StatusCode, logMessage);
            }
            catch (HttpRequestException)
            {
                throw; // propaga 4xx al llamador
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "✗ Attempt {Attempt}/{MaxRetries} exception: {Message}",
                    attempt, MaxRetries, logMessage);
            }

            if (attempt < MaxRetries)
                await Task.Delay(RetryDelayMs * attempt);
        }

        logger.LogError("✗ Failed after {MaxRetries} attempts: {Message}", MaxRetries, logMessage);
        throw new HttpRequestException($"PHP API failed after {MaxRetries} attempts: {logMessage}");
    }

    private async Task SendMetadataWithRetryAsync(string fullUrl, object payload, string apiKey, string logMessage)
    {
        for (int attempt = 1; attempt <= MaxRetries; attempt++)
        {
            try
            {
                var request = new HttpRequestMessage(HttpMethod.Post, fullUrl)
                {
                    Content = JsonContent.Create(payload)
                };

                if (!string.IsNullOrEmpty(apiKey))
                    request.Headers.Add("X-API-Key", apiKey);

                var response = await httpClient.SendAsync(request);

                if (response.IsSuccessStatusCode)
                {
                    logger.LogInformation("✓ {Message}", logMessage);
                    return;
                }

                if ((int)response.StatusCode < 500)
                {
                    logger.LogWarning("✗ API error [{Status}] {Message}",
                        response.StatusCode, logMessage);
                    return;
                }

                logger.LogWarning("✗ Attempt {Attempt}/{MaxRetries} failed [{Status}]: {Message}",
                    attempt, MaxRetries, response.StatusCode, logMessage);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "✗ Attempt {Attempt}/{MaxRetries} exception: {Message}",
                    attempt, MaxRetries, logMessage);
            }

            if (attempt < MaxRetries)
                await Task.Delay(RetryDelayMs * attempt);
        }

        logger.LogError("✗ Failed after {MaxRetries} attempts: {Message}", MaxRetries, logMessage);
    }
}
