using MediatR;
using QualityDMS.Application.Documents.DTOs;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Application.Documents.Queries.GetDocumentById;

public class GetDocumentByIdQueryHandler(IDocumentRepository documentRepository)
    : IRequestHandler<GetDocumentByIdQuery, DocumentDetailDto?>
{
    public async Task<DocumentDetailDto?> Handle(GetDocumentByIdQuery query, CancellationToken ct)
    {
        var doc = await documentRepository.GetByIdWithVersionsAsync(query.DocumentId, ct);
        if (doc is null) return null;

        return new DocumentDetailDto
        {
            DocumentId = doc.DocumentId,
            Code = doc.Code,
            Title = doc.Title,
            Description = doc.Description,
            Status = doc.Status,
            CompanyId = doc.CompanyId,
            CompanyName = doc.Company?.Name ?? string.Empty,
            CategoryId = doc.CategoryId,
            CategoryName = doc.Category?.Name ?? string.Empty,
            DepartmentId = doc.DepartmentId,
            DepartmentName = doc.Department?.Name ?? string.Empty,
            WorkflowTemplateId = doc.WorkflowTemplateId,
            EffectiveDate = doc.EffectiveDate,
            ExpirationDate = doc.ExpirationDate,
            HasEditableDraft = doc.HasEditableDraft,
            EditableDraftNumber = doc.EditableDraftNumber,
            NextReviewDate = doc.NextReviewDate,
            CreatedAt = doc.CreatedAt,
            CreatedBy = doc.CreatedBy,
            Versions = doc.Versions.OrderByDescending(v => v.CreatedAt).Select(v => new DocumentVersionDto
            {
                VersionId = v.VersionId,
                VersionNumber = v.VersionNumber,
                FileName = v.FileName,
                FileSizeBytes = v.FileSizeBytes,
                ChangeLog = v.ChangeLog,
                IsCurrent = v.IsCurrent,
                Status = v.Status,
                ApprovedAt = v.ApprovedAt,
                ObsoletedAt = v.ObsoletedAt,
                CreatedAt = v.CreatedAt,
                CreatedBy = v.CreatedBy
            })
        };
    }
}
