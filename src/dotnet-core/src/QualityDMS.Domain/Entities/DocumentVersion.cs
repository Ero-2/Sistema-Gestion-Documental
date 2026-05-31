using QualityDMS.Domain.Common;
using QualityDMS.Domain.Enums;

namespace QualityDMS.Domain.Entities;

public class DocumentVersion : AuditableEntity
{
    public int VersionId { get; set; }
    public int DocumentId { get; set; }
    public string VersionNumber { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public string? FileName { get; set; }
    public long FileSizeBytes { get; set; }
    public string? ContentType { get; set; }
    public string? ChangeLog { get; set; }

    /// <summary>Estado de esta versión (fuente de verdad).</summary>
    public VersionStatus Status { get; set; } = VersionStatus.Draft;

    /// <summary>Única versión aprobada vigente del documento (máx. una en true).</summary>
    public bool IsCurrent { get; set; }

    public string? ApprovedBy { get; set; }
    public DateTime? ApprovedAt { get; set; }
    public DateTime? ObsoletedAt { get; set; }

    /// <summary>Borrador del que se selló esta versión aprobada (trazabilidad 0.4 → 1.0).</summary>
    public int? SourceVersionId { get; set; }

    public Document Document { get; set; } = null!;

    /// <summary>Crea un BORRADOR (X.Y, no publicable). El número lo asigna el agregado Document.</summary>
    public static DocumentVersion Create(int documentId, string versionNumber, string filePath,
        string fileName, long fileSizeBytes, string contentType, string createdBy, string? changeLog = null)
    {
        return new DocumentVersion
        {
            DocumentId = documentId,
            VersionNumber = versionNumber,
            FilePath = filePath,
            FileName = fileName,
            FileSizeBytes = fileSizeBytes,
            ContentType = contentType,
            ChangeLog = changeLog,
            Status = VersionStatus.Draft,
            IsCurrent = false,
            CreatedBy = createdBy
        };
    }

    /// <summary>
    /// Crea una versión APROBADA inmutable (X.0) sellada a partir de un borrador.
    /// Copia los datos del archivo del borrador origen; no se vuelve a subir.
    /// </summary>
    public static DocumentVersion CreateApproved(int documentId, string versionNumber,
        DocumentVersion source, string approvedBy)
    {
        var now = DateTime.UtcNow;
        return new DocumentVersion
        {
            DocumentId = documentId,
            VersionNumber = versionNumber,
            FilePath = source.FilePath,
            FileName = source.FileName,
            FileSizeBytes = source.FileSizeBytes,
            ContentType = source.ContentType,
            ChangeLog = source.ChangeLog,
            Status = VersionStatus.Approved,
            IsCurrent = true,
            ApprovedBy = approvedBy,
            ApprovedAt = now,
            SourceVersionId = source.VersionId,
            CreatedBy = approvedBy
        };
    }

    /// <summary>Marca esta versión aprobada como obsoleta (reemplazada por una nueva X.0).</summary>
    public void MakeObsolete()
    {
        Status = VersionStatus.Obsolete;
        IsCurrent = false;
        ObsoletedAt = DateTime.UtcNow;
    }
}
