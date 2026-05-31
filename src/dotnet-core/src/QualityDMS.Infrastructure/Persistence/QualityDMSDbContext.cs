using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using QualityDMS.Domain.Entities;
using QualityDMS.Domain.Interfaces;
using QualityDMS.Infrastructure.Identity;
using System.Reflection;

namespace QualityDMS.Infrastructure.Persistence;

public class QualityDMSDbContext(DbContextOptions<QualityDMSDbContext> options, ICurrentUserService currentUser)
    : IdentityDbContext<ApplicationUser>(options)
{
    // Aislamiento multiempresa: cuando hay tenant, las consultas se acotan a su CompanyId.
    // SuperAdmin (o contexto sin usuario: seeding/jobs) ve todas las empresas.
    private bool TenantBypass => currentUser.IsSuperAdmin || currentUser.CompanyId is null;
    private int CurrentCompanyId => currentUser.CompanyId ?? 0;

    public DbSet<Company> Companies => Set<Company>();
    public DbSet<Document> Documents => Set<Document>();
    public DbSet<DocumentVersion> DocumentVersions => Set<DocumentVersion>();
    public DbSet<DocumentCategory> DocumentCategories => Set<DocumentCategory>();
    public DbSet<Department> Departments => Set<Department>();
    public DbSet<WorkflowTemplate> WorkflowTemplates => Set<WorkflowTemplate>();
    public DbSet<WorkflowStep> WorkflowSteps => Set<WorkflowStep>();
    public DbSet<WorkflowInstance> WorkflowInstances => Set<WorkflowInstance>();
    public DbSet<WorkflowAction> WorkflowActions => Set<WorkflowAction>();
    public DbSet<QualityAudit> QualityAudits => Set<QualityAudit>();
    public DbSet<AuditFinding> AuditFindings => Set<AuditFinding>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<ControlledDistribution> ControlledDistributions => Set<ControlledDistribution>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        builder.ApplyConfigurationsFromAssembly(Assembly.GetExecutingAssembly());

        builder.Entity<ApplicationUser>()
            .Ignore(u => u.FullName);

        // Filtros globales de empresa (tenant). Referencian campos de instancia →
        // EF los reevalúa por consulta. Bypass para SuperAdmin / contexto sin usuario.
        builder.Entity<Document>().HasQueryFilter(e => TenantBypass || e.CompanyId == CurrentCompanyId);
        builder.Entity<Department>().HasQueryFilter(e => TenantBypass || e.CompanyId == CurrentCompanyId);
        builder.Entity<DocumentCategory>().HasQueryFilter(e => TenantBypass || e.CompanyId == CurrentCompanyId);
        builder.Entity<WorkflowTemplate>().HasQueryFilter(e => TenantBypass || e.CompanyId == CurrentCompanyId);
    }

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        foreach (var entry in ChangeTracker.Entries<Domain.Common.AuditableEntity>())
        {
            switch (entry.State)
            {
                case EntityState.Added:
                    entry.Entity.CreatedAt = DateTime.UtcNow;
                    break;
                case EntityState.Modified:
                    entry.Entity.UpdatedAt = DateTime.UtcNow;
                    break;
            }
        }
        return base.SaveChangesAsync(cancellationToken);
    }
}
