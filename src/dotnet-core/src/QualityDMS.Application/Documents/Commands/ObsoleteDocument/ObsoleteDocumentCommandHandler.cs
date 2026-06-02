using MediatR;
using QualityDMS.Application.Common.Exceptions;
using QualityDMS.Domain.Common;
using QualityDMS.Domain.Entities;
using QualityDMS.Domain.Interfaces;

namespace QualityDMS.Application.Documents.Commands.ObsoleteDocument;

public class ObsoleteDocumentCommandHandler(
    IDocumentRepository documentRepository,
    IUnitOfWork uow,
    IPhpSyncService phpSync,
    IPublicDmsWebhookService webhook) : IRequestHandler<ObsoleteDocumentCommand, Result>
{
    public async Task<Result> Handle(ObsoleteDocumentCommand cmd, CancellationToken ct)
    {
        var document = await documentRepository.GetByIdWithVersionsAsync(cmd.DocumentId, ct)
            ?? throw new NotFoundException(nameof(Document), cmd.DocumentId);

        // Solo un documento con versión vigente aprobada puede obsoletarse (sin reemplazo).
        if (document.CurrentApprovedVersion() is null)
            return Result.Failure("Solo se puede obsoletar un documento con una versión vigente aprobada.");

        document.Obsolete();
        documentRepository.Update(document);
        await uow.SaveChangesAsync(ct);

        // Propagar obsolescencia a PostgreSQL y MongoDB
        try
        {
            await phpSync.ObsoleteDocumentAsync(document.DocumentId, "Retirado manualmente");
            await webhook.ObsoleteAsync(document.DocumentId);
        }
        catch
        {
            // APIs externas no críticas; el doc ya está obsoleto en SQL Server
        }

        return Result.Success();
    }
}
