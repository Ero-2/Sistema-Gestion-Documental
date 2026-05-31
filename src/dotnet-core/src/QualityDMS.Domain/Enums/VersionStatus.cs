namespace QualityDMS.Domain.Enums;

/// <summary>
/// Estado por versión (fuente de verdad del versionado).
/// Draft/PendingApproval/Rejected = borradores X.Y (NO publicables).
/// Approved = versión sellada X.0 (vigente si IsCurrent, histórica si no).
/// Obsolete = versión X.0 reemplazada por una X+1.0.
/// </summary>
public enum VersionStatus
{
    Draft = 1,
    PendingApproval = 2,
    Approved = 3,
    Obsolete = 4,
    Rejected = 5
}
