using MediatR;
using QualityDMS.Domain.Common;
using QualityDMS.Domain.Entities;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Application.Documents.Commands.CreateDocument;

public class CreateDocumentCommandHandler(
    IDocumentRepository documentRepository,
    IFileStorageService fileStorage,
    ICurrentUserService currentUser,
    IUnitOfWork uow) : IRequestHandler<CreateDocumentCommand, Result<int>>
{
    public async Task<Result<int>> Handle(CreateDocumentCommand cmd, CancellationToken ct)
    {
        if (await documentRepository.CodeExistsAsync(cmd.Code, ct: ct))
            return Result.Failure<int>($"El código '{cmd.Code}' ya existe.");

        var (filePath, sizeBytes) = await fileStorage.UploadAsync(
            cmd.FileStream, cmd.FileName, cmd.ContentType, ct);

        // El documento hereda la empresa del autor (aislamiento multiempresa).
        var companyId = currentUser.CompanyId ?? 0;
        var document = Document.Create(cmd.Code, cmd.Title, cmd.CategoryId, cmd.DepartmentId, currentUser.UserId, companyId);
        document.Description = cmd.Description;
        document.WorkflowTemplateId = cmd.WorkflowTemplateId;
        document.NextReviewDate = cmd.NextReviewDate;

        await documentRepository.AddAsync(document, ct);
        await uow.SaveChangesAsync(ct);

        // Primer borrador: 0.1 (no publicable hasta su primera aprobación → 1.0).
        document.AddDraftVersion(
            filePath, cmd.FileName, sizeBytes, cmd.ContentType, currentUser.UserId);

        documentRepository.Update(document);
        await uow.SaveChangesAsync(ct);

        return Result.Success(document.DocumentId);
    }
}
