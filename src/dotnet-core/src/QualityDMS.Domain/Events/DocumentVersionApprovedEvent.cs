using QualityDMS.Domain.Common;
using QualityDMS.Domain.Entities;

namespace QualityDMS.Domain.Events;

/// <summary>
/// Se dispara cuando un borrador se sella como versión aprobada X.0.
/// Lleva la nueva versión vigente y, si existía, la versión que queda obsoleta.
/// Es el único evento que publica versiones aprobadas a PHP/Mongo y, a la vez,
/// indica qué versión anterior debe marcarse obsoleta (operación atómica).
/// </summary>
public class DocumentVersionApprovedEvent(
    Document document,
    DocumentVersion approvedVersion,
    DocumentVersion? supersededVersion,
    string approvedBy) : DomainEvent
{
    public Document Document { get; } = document;
    public DocumentVersion ApprovedVersion { get; } = approvedVersion;
    public DocumentVersion? SupersededVersion { get; } = supersededVersion;
    public string ApprovedBy { get; } = approvedBy;
}
