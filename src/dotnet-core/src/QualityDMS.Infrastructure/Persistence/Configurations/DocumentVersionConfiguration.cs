using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using QualityDMS.Domain.Entities;

namespace QualityDMS.Infrastructure.Persistence.Configurations;

public class DocumentVersionConfiguration : IEntityTypeConfiguration<DocumentVersion>
{
    public void Configure(EntityTypeBuilder<DocumentVersion> builder)
    {
        builder.ToTable("DocumentVersions");
        builder.HasKey(x => x.VersionId);

        builder.Property(x => x.VersionNumber).HasMaxLength(20).IsRequired();
        builder.Property(x => x.FilePath).HasMaxLength(1000).IsRequired();
        builder.Property(x => x.FileName).HasMaxLength(255);
        builder.Property(x => x.ContentType).HasMaxLength(100);
        builder.Property(x => x.ChangeLog).HasMaxLength(2000);
        builder.Property(x => x.CreatedBy).HasMaxLength(450);
        builder.Property(x => x.ApprovedBy).HasMaxLength(450);
        builder.Property(x => x.Status).HasConversion<int>();

        builder.HasIndex(x => new { x.DocumentId, x.VersionNumber }).IsUnique();
        builder.HasIndex(x => x.Status);

        // Garantía dura: máximo UNA versión vigente por documento.
        builder.HasIndex(x => x.DocumentId)
               .IsUnique()
               .HasFilter("[IsCurrent] = 1")
               .HasDatabaseName("UX_DocumentVersions_OneCurrent");
    }
}
