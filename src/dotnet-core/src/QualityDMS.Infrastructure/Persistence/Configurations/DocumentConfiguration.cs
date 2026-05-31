using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using QualityDMS.Domain.Entities;
using QualityDMS.Domain.Enums;

namespace QualityDMS.Infrastructure.Persistence.Configurations;

public class DocumentConfiguration : IEntityTypeConfiguration<Document>
{
    public void Configure(EntityTypeBuilder<Document> builder)
    {
        builder.ToTable("Documents");
        builder.HasKey(x => x.DocumentId);

        builder.Property(x => x.Code).HasMaxLength(50).IsRequired();
        builder.Property(x => x.Title).HasMaxLength(500).IsRequired();
        builder.Property(x => x.Description).HasMaxLength(2000);
        builder.Property(x => x.Status)
               .HasColumnName("CurrentStatus")
               .HasConversion<int>();
        builder.Property(x => x.CreatedBy).HasMaxLength(450);
        builder.Property(x => x.UpdatedBy).HasMaxLength(450);

        builder.HasIndex(x => new { x.CompanyId, x.Code }).IsUnique();
        builder.HasIndex(x => x.NextReviewDate);
        builder.HasIndex(x => x.CategoryId);

        builder.HasOne(x => x.WorkflowTemplate)
               .WithMany(x => x.Documents)
               .HasForeignKey(x => x.WorkflowTemplateId)
               .OnDelete(DeleteBehavior.NoAction)
               .IsRequired(false);

        builder.HasMany(x => x.Versions)
               .WithOne(x => x.Document)
               .HasForeignKey(x => x.DocumentId)
               .OnDelete(DeleteBehavior.Cascade);

        builder.HasMany(x => x.WorkflowInstances)
               .WithOne(x => x.Document)
               .HasForeignKey(x => x.DocumentId)
               .OnDelete(DeleteBehavior.Restrict);

        builder.HasMany(x => x.Distributions)
               .WithOne(x => x.Document)
               .HasForeignKey(x => x.DocumentId)
               .OnDelete(DeleteBehavior.Cascade);

        builder.Ignore(x => x.DomainEvents);
    }
}
