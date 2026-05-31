using Microsoft.Extensions.Logging;
using QualityDMS.Domain.Interfaces;
using System.Net.Http.Json;

namespace QualityDMS.Infrastructure.Services;

public class PublicDmsWebhookService(
    HttpClient httpClient,
    ILogger<PublicDmsWebhookService> logger) : IPublicDmsWebhookService
{
    public async Task NotifyDocumentApprovedAsync(
        int documentId,
        string code,
        string title,
        string categoryName,
        string departmentName,
        string version,
        string fileUrl,
        int companyId = 0,
        string companyName = "")
    {
        try
        {
            var payload = new
            {
                postgres_id     = documentId.ToString(),
                code            = code,
                title           = title,
                category_name   = categoryName,
                department_name = departmentName,
                version         = string.IsNullOrEmpty(version) ? "1.0" : version,
                file_url        = fileUrl ?? "",
                is_active       = true,
                company_id      = companyId,
                company_name    = companyName,
            };

            var response = await httpClient.PostAsJsonAsync("/indexer/upsert", payload);

            if (!response.IsSuccessStatusCode)
                logger.LogWarning("Webhook upsert [{Status}] document {Id}",
                    response.StatusCode, documentId);
            else
                logger.LogInformation("Webhook upsert: document {Id} indexed in MongoDB", documentId);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Webhook upsert failed for document {Id}", documentId);
        }
    }
}
