using QualityDMS.Domain.Common;
using QualityDMS.Domain.Enums;
using QualityDMS.Domain.Events;

namespace QualityDMS.Domain.Entities;

public class Document : AuditableEntity
{
    private readonly List<DocumentVersion> _versions = new();
    private readonly List<DomainEvent> _domainEvents = new();

    public int DocumentId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }

    /// <summary>
    /// Resumen DERIVADO del ciclo de vida. NO es la fuente de verdad: lo recalcula
    /// <see cref="RecalculateStatus"/> desde las versiones. Se persiste solo como caché
    /// para filtros/UI. La verdad por versión vive en <see cref="DocumentVersion.Status"/>.
    /// </summary>
    public DocumentStatus Status { get; set; } = DocumentStatus.Draft;

    public int CategoryId { get; set; }
    public int DepartmentId { get; set; }
    public int? WorkflowTemplateId { get; set; }
    public DateTime? EffectiveDate { get; set; }
    public DateTime? ExpirationDate { get; set; }
    public DateTime? NextReviewDate { get; set; }
    public bool IsActive { get; set; } = true;

    public DocumentCategory Category { get; set; } = null!;
    public Department Department { get; set; } = null!;
    public WorkflowTemplate? WorkflowTemplate { get; set; }
    public IReadOnlyCollection<DocumentVersion> Versions => _versions.AsReadOnly();
    public IReadOnlyCollection<DomainEvent> DomainEvents => _domainEvents.AsReadOnly();
    public ICollection<WorkflowInstance> WorkflowInstances { get; set; } = new List<WorkflowInstance>();
    public ICollection<ControlledDistribution> Distributions { get; set; } = new List<ControlledDistribution>();

    public static Document Create(string code, string title, int categoryId, int departmentId, string createdBy)
    {
        var doc = new Document
        {
            Code = code,
            Title = title,
            CategoryId = categoryId,
            DepartmentId = departmentId,
            Status = DocumentStatus.Draft,
            CreatedBy = createdBy
        };
        doc._domainEvents.Add(new DocumentCreatedEvent(doc));
        return doc;
    }

    // ── Versionado ────────────────────────────────────────────────────────────

    /// <summary>Añade una versión ya construida (uso de seeders / persistencia).</summary>
    public void AddVersion(DocumentVersion version) => _versions.Add(version);

    /// <summary>
    /// Crea un BORRADOR con el siguiente número (0.1, 0.2… antes de aprobar;
    /// 1.1, 1.2… tras la 1.0; 2.1… tras la 2.0). El minor avanza dentro del major
    /// aprobado actual; el major solo cambia al aprobar.
    /// </summary>
    public DocumentVersion AddDraftVersion(string filePath, string fileName, long fileSizeBytes,
        string contentType, string createdBy, string? changeLog = null)
    {
        var major = HighestApprovedMajor();
        var minor = _versions
            .Where(v => MajorOf(v.VersionNumber) == major)
            .Select(v => MinorOf(v.VersionNumber))
            .DefaultIfEmpty(0)
            .Max() + 1;

        var version = DocumentVersion.Create(
            DocumentId, $"{major}.{minor}", filePath, fileName, fileSizeBytes, contentType, createdBy, changeLog);
        _versions.Add(version);
        RecalculateStatus();
        return version;
    }

    /// <summary>Envía el último borrador a aprobación. Devuelve la versión en revisión.</summary>
    public DocumentVersion SubmitForApproval()
    {
        var draft = LatestEditableDraft()
            ?? throw new InvalidOperationException("No hay borrador editable para enviar a aprobación.");

        draft.Status = VersionStatus.PendingApproval;
        RecalculateStatus();
        _domainEvents.Add(new DocumentSubmittedEvent(this));
        return draft;
    }

    /// <summary>
    /// Sella el borrador en revisión como nueva versión aprobada X.0 (inmutable),
    /// obsoleta la vigente anterior y dispara <see cref="DocumentVersionApprovedEvent"/>.
    /// Devuelve la nueva versión aprobada.
    /// </summary>
    public DocumentVersion Approve(string approvedBy)
    {
        var pending = _versions.FirstOrDefault(v => v.Status == VersionStatus.PendingApproval)
            ?? throw new InvalidOperationException("No hay versión en revisión para aprobar.");

        var superseded = _versions.FirstOrDefault(v => v.IsCurrent);
        superseded?.MakeObsolete();

        var newMajor = HighestApprovedMajor() + 1;
        var approved = DocumentVersion.CreateApproved(DocumentId, $"{newMajor}.0", pending, approvedBy);
        _versions.Add(approved);

        // El borrador aprobado vuelve a Draft como historial (su trazabilidad queda
        // en approved.SourceVersionId). No se elimina.
        pending.Status = VersionStatus.Draft;

        RecalculateStatus();
        _domainEvents.Add(new DocumentVersionApprovedEvent(this, approved, superseded, approvedBy));
        return approved;
    }

    public void Reject(string rejectedBy, string reason)
    {
        var pending = _versions.FirstOrDefault(v => v.Status == VersionStatus.PendingApproval)
            ?? throw new InvalidOperationException("No hay versión en revisión para rechazar.");

        pending.Status = VersionStatus.Rejected;
        RecalculateStatus();
        _domainEvents.Add(new DocumentRejectedEvent(this, rejectedBy, reason));
    }

    /// <summary>Da de baja el documento: obsoleta la versión vigente (sin reemplazo).</summary>
    public void Obsolete()
    {
        var current = _versions.FirstOrDefault(v => v.IsCurrent);
        current?.MakeObsolete();
        RecalculateStatus();
        _domainEvents.Add(new DocumentObsoletedEvent(this));
    }

    /// <summary>Versión aprobada vigente, o null si el documento aún no tiene una.</summary>
    public DocumentVersion? CurrentApprovedVersion()
        => _versions.FirstOrDefault(v => v.IsCurrent && v.Status == VersionStatus.Approved);

    /// <summary>
    /// Recalcula el caché <see cref="Status"/>, <see cref="EffectiveDate"/> e
    /// <see cref="IsActive"/> desde las versiones. Único punto que escribe Status.
    /// </summary>
    public void RecalculateStatus()
    {
        var current = CurrentApprovedVersion();

        if (current is not null)
            Status = DocumentStatus.Approved;
        else if (_versions.Any(v => v.Status == VersionStatus.PendingApproval))
            Status = DocumentStatus.PendingApproval;
        else if (_versions.Any(v => v.Status == VersionStatus.Obsolete))
            Status = DocumentStatus.Obsolete;       // tuvo vigente, ahora dada de baja
        else if (_versions.Any(v => v.Status == VersionStatus.Rejected))
            Status = DocumentStatus.Rejected;
        else
            Status = DocumentStatus.Draft;

        EffectiveDate = current?.ApprovedAt;
        IsActive = Status != DocumentStatus.Obsolete;
    }

    public void ClearDomainEvents() => _domainEvents.Clear();

    // ── Helpers de numeración ───────────────────────────────────────────────────

    /// <summary>Mayor "major" entre versiones aprobadas/obsoletas (0 si aún no hay aprobada).</summary>
    private int HighestApprovedMajor()
        => _versions
            .Where(v => v.Status is VersionStatus.Approved or VersionStatus.Obsolete)
            .Select(v => MajorOf(v.VersionNumber))
            .DefaultIfEmpty(0)
            .Max();

    private DocumentVersion? LatestEditableDraft()
        => _versions
            .Where(v => v.Status is VersionStatus.Draft or VersionStatus.Rejected)
            .OrderByDescending(v => MajorOf(v.VersionNumber))
            .ThenByDescending(v => MinorOf(v.VersionNumber))
            .FirstOrDefault();

    private static int MajorOf(string versionNumber)
        => int.TryParse(versionNumber.Split('.')[0], out var m) ? m : 0;

    private static int MinorOf(string versionNumber)
    {
        var parts = versionNumber.Split('.');
        return parts.Length > 1 && int.TryParse(parts[1], out var m) ? m : 0;
    }
}
