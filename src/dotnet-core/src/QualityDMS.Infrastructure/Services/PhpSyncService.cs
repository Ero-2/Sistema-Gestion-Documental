using System.Net.Http.Json;
using Microsoft.Extensions.Logging;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Infrastructure.Services;

public class PhpSyncService(
    HttpClient httpClient,
    ILogger<PhpSyncService> logger) : IPhpSyncService
{
    public async Task TriggerSyncAsync(int documentId)
    {
        try
        {
            var response = await httpClient.PostAsJsonAsync(
                "/sync/trigger_sync.php",
                new { document_id = documentId });

            if (!response.IsSuccessStatusCode)
                logger.LogWarning("PHP sync trigger failed [{Status}]", response.StatusCode);
            else
                logger.LogInformation("PHP sync triggered for document {DocumentId}", documentId);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "PHP sync trigger error");
        }
    }
}
