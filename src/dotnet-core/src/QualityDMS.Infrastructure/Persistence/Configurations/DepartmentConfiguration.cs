using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using QualityDMS.Domain.Entities;

namespace QualityDMS.Infrastructure.Persistence.Configurations;

public class DepartmentConfiguration : IEntityTypeConfiguration<Department>
{
    public void Configure(EntityTypeBuilder<Department> builder)
    {
        builder.ToTable("Departments");
        builder.HasKey(x => x.DepartmentId);

        builder.Property(x => x.Code).HasMaxLength(20).IsRequired();
        builder.Property(x => x.Name).HasMaxLength(150).IsRequired();
        builder.Property(x => x.Description).HasMaxLength(500);
        builder.Property(x => x.ManagerName).HasMaxLength(200);
        builder.Property(x => x.CreatedBy).HasMaxLength(450);

        builder.HasIndex(x => new { x.CompanyId, x.Code }).IsUnique();

        builder.HasMany(x => x.Documents)
               .WithOne(x => x.Department)
               .HasForeignKey(x => x.DepartmentId)
               .OnDelete(DeleteBehavior.Restrict);
    }
}
