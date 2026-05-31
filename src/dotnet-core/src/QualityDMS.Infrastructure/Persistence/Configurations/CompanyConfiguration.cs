using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using QualityDMS.Domain.Entities;

namespace QualityDMS.Infrastructure.Persistence.Configurations;

public class CompanyConfiguration : IEntityTypeConfiguration<Company>
{
    public void Configure(EntityTypeBuilder<Company> builder)
    {
        builder.ToTable("Companies");
        builder.HasKey(x => x.CompanyId);

        builder.Property(x => x.Code).HasMaxLength(20).IsRequired();
        builder.Property(x => x.Name).HasMaxLength(200).IsRequired();
        builder.Property(x => x.TaxId).HasMaxLength(50);
        builder.Property(x => x.CreatedBy).HasMaxLength(450);

        builder.HasIndex(x => x.Code).IsUnique();

        builder.HasMany(x => x.Documents).WithOne(x => x.Company)
               .HasForeignKey(x => x.CompanyId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.Departments).WithOne(x => x.Company)
               .HasForeignKey(x => x.CompanyId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.Categories).WithOne(x => x.Company)
               .HasForeignKey(x => x.CompanyId).OnDelete(DeleteBehavior.Restrict);
        builder.HasMany(x => x.WorkflowTemplates).WithOne(x => x.Company)
               .HasForeignKey(x => x.CompanyId).OnDelete(DeleteBehavior.Restrict);
    }
}
