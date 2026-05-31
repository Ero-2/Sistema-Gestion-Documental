namespace QualityDMS.Domain.Interfaces;

public interface IPublicDmsWebhookService
{
    /// <summary>
    /// Push completo a FastAPI (/indexer/upsert) para indexar metadatos +
    /// extraer contenido del archivo (full-text) en MongoDB.
    /// FastAPI NO consulta SQL Server: recibe todos los datos por este evento
    /// y lee el archivo del volumen compartido.
    /// </summary>
    Task NotifyDocumentApprovedAsync(
        int documentId,
        string code,
        string title,
        string categoryName,
        string departmentName,
        string version,
        string fileUrl,
        int companyId = 0,
        string companyName = "");
}
