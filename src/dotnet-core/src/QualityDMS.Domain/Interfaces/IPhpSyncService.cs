namespace QualityDMS.Domain.Interfaces;

public interface IPhpSyncService
{
    // Document events → PostgreSQL
    Task ApproveDocumentAsync(int documentId, string code, string title,
        int categoryId, string categoryName, int departmentId, string departmentName,
        string version, string fileUrl, DateTime? effectiveDate, DateTime? expirationDate,
        DateTime? approvedAt = null, int companyId = 0, string companyName = "");

    Task UpdateDocumentAsync(int documentId, bool isActive,
        DateTime? effectiveDate, DateTime? expirationDate, string reason = null);

    Task VersionDocumentAsync(int documentId, string version, string fileUrl);

    Task ObsoleteDocumentAsync(int documentId, string obsoleteReason);

    // Metadata events → MongoDB
    Task RegisterMetadataAsync(int postgresId, string code, string title,
        string categoryName, string departmentName, string fileUrl, string version);

    Task UpdateMetadataAsync(int postgresId, Dictionary<string, object> updates);

    Task LogMetadataHistoryAsync(int postgresId, string action, Dictionary<string, object> details);
}
