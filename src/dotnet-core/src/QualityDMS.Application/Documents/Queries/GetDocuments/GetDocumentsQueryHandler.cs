using MediatR;
using QualityDMS.Application.Common.Models;
using QualityDMS.Application.Documents.DTOs;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Application.Documents.Queries.GetDocuments;

public class GetDocumentsQueryHandler(IDocumentRepository documentRepository)
    : IRequestHandler<GetDocumentsQuery, PagedResult<DocumentDto>>
{
    public async Task<PagedResult<DocumentDto>> Handle(GetDocumentsQuery query, CancellationToken ct)
    {
        var (items, totalCount) = await documentRepository.GetPagedAsync(
            query.CategoryId, query.DepartmentId, query.Status,
            query.SearchTerm, query.Page, query.PageSize, ct);

        var dtos = items.Select(d => new DocumentDto
        {
            DocumentId = d.DocumentId,
            Code = d.Code,
            Title = d.Title,
            Status = d.Status,
            CompanyId = d.CompanyId,
            CompanyName = d.Company?.Name ?? string.Empty,
            CategoryName = d.Category?.Name ?? string.Empty,
            DepartmentName = d.Department?.Name ?? string.Empty,
            CurrentVersion = d.Versions.OrderByDescending(v => v.CreatedAt).FirstOrDefault()?.VersionNumber,
            NextReviewDate = d.NextReviewDate,
            CreatedAt = d.CreatedAt,
            CreatedBy = d.CreatedBy
        });

        return new PagedResult<DocumentDto>
        {
            Items = dtos,
            TotalCount = totalCount,
            Page = query.Page,
            PageSize = query.PageSize
        };
    }
}
