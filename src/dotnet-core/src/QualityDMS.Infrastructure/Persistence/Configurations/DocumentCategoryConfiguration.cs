using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using QualityDMS.Domain.Entities;

namespace QualityDMS.Infrastructure.Persistence.Configurations;

public class DocumentCategoryConfiguration : IEntityTypeConfiguration<DocumentCategory>
{
    public void Configure(EntityTypeBuilder<DocumentCategory> builder)
    {
        builder.ToTable("DocumentCategories");
        builder.HasKey(x => x.CategoryId);

        builder.Property(x => x.Code).HasMaxLength(20).IsRequired();
        builder.Property(x => x.Name).HasMaxLength(150).IsRequired();
        builder.Property(x => x.Description).HasMaxLength(500);
        builder.Property(x => x.CreatedBy).HasMaxLength(450);

        builder.HasIndex(x => new { x.CompanyId, x.Code }).IsUnique();

        builder.HasMany(x => x.SubCategories)
               .WithOne(x => x.ParentCategory)
               .HasForeignKey(x => x.ParentCategoryId)
               .OnDelete(DeleteBehavior.Restrict);

        builder.HasMany(x => x.Documents)
               .WithOne(x => x.Category)
               .HasForeignKey(x => x.CategoryId)
               .OnDelete(DeleteBehavior.Restrict);
    }
}
