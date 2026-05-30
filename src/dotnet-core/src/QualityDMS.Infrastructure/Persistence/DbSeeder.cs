using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using QualityDMS.Domain.Entities;
using QualityDMS.Domain.Enums;
using QualityDMS.Infrastructure.Identity;

namespace QualityDMS.Infrastructure.Persistence;

/// <summary>
/// Precarga datos de prueba para permitir pruebas funcionales inmediatas
/// sin captura manual. Solo siembra en entorno de pruebas (Development).
/// Idempotente: cada bloque se omite si la tabla ya tiene datos.
///
/// Los usuarios se crean con UserManager (passwords con hash) porque .NET es
/// la única fuente de auth/roles del sistema (arquitectura desacoplada).
/// </summary>
public static class DbSeeder
{
    // Roles del sistema.
    public const string RoleAdmin          = "Admin";
    public const string RoleQualityManager = "QualityManager";
    public const string RoleApprover       = "Approver";
    public const string RoleAuthor         = "Author";
    public const string RoleViewer         = "Viewer";

    // Password común de los usuarios de prueba.
    // Cumple política Identity: >=12, mayúscula, dígito y símbolo.
    private const string SeedPassword = "Calidad#2026Dev";

    // Marcador de autoría para registros sembrados (CreatedBy es requerido).
    private const string SeedBy = "seed";

    public static async Task SeedAsync(IServiceProvider services)
    {
        var logger      = services.GetRequiredService<ILogger<QualityDMSDbContext>>();
        var db          = services.GetRequiredService<QualityDMSDbContext>();
        var roleManager = services.GetRequiredService<RoleManager<IdentityRole>>();
        var userManager = services.GetRequiredService<UserManager<ApplicationUser>>();

        await SeedRolesAsync(roleManager, logger);
        var depts    = await SeedDepartmentsAsync(db, logger);
        await SeedUsersAsync(userManager, depts, logger);
        var cats     = await SeedCategoriesAsync(db, logger);
        var template = await SeedWorkflowAsync(db, logger);
        await SeedDocumentsAsync(db, userManager, depts, cats, template, logger);

        logger.LogInformation("DbSeeder: datos de prueba listos.");
    }

    // ── Roles ──────────────────────────────────────────────────────────────
    private static async Task SeedRolesAsync(RoleManager<IdentityRole> roleManager, ILogger logger)
    {
        string[] roles = [RoleAdmin, RoleQualityManager, RoleApprover, RoleAuthor, RoleViewer];
        foreach (var role in roles)
        {
            if (!await roleManager.RoleExistsAsync(role))
            {
                await roleManager.CreateAsync(new IdentityRole(role));
                logger.LogInformation("DbSeeder: rol creado {Role}", role);
            }
        }
    }

    // ── Departamentos ───────────────────────────────────────────────────────
    private static async Task<Dictionary<string, int>> SeedDepartmentsAsync(
        QualityDMSDbContext db, ILogger logger)
    {
        if (!await db.Departments.AnyAsync())
        {
            db.Departments.AddRange(
                new Department { Code = "CAL",  Name = "Calidad",          Description = "Gestión de calidad y mejora continua", ManagerName = "Gerente de Calidad", CreatedBy = SeedBy },
                new Department { Code = "OPE",  Name = "Operaciones",      Description = "Operación y producción",                CreatedBy = SeedBy },
                new Department { Code = "RRHH", Name = "Recursos Humanos", Description = "Gestión del personal",                  CreatedBy = SeedBy },
                new Department { Code = "TI",   Name = "Tecnología",       Description = "Sistemas e infraestructura",            CreatedBy = SeedBy }
            );
            await db.SaveChangesAsync();
            logger.LogInformation("DbSeeder: departamentos sembrados");
        }

        return await db.Departments.ToDictionaryAsync(d => d.Name, d => d.DepartmentId);
    }

    // ── Usuarios ────────────────────────────────────────────────────────────
    private static async Task SeedUsersAsync(
        UserManager<ApplicationUser> userManager, Dictionary<string, int> depts, ILogger logger)
    {
        (string Email, string First, string Last, string Dept, string Role)[] users =
        [
            ("admin@qualitydms.local",      "Administrador", "del Sistema", "Calidad",          RoleAdmin),
            ("calidad@qualitydms.local",    "Gerente",       "de Calidad",  "Calidad",          RoleQualityManager),
            ("aprobador1@qualitydms.local", "Juan",          "Pérez",       "Calidad",          RoleApprover),
            ("aprobador2@qualitydms.local", "María",         "García",      "Operaciones",      RoleApprover),
            ("autor@qualitydms.local",      "Carlos",        "López",       "Operaciones",      RoleAuthor),
            ("lector@qualitydms.local",     "Ana",           "Torres",      "Recursos Humanos", RoleViewer),
        ];

        foreach (var (email, first, last, dept, role) in users)
        {
            if (await userManager.FindByEmailAsync(email) is not null) continue;

            var user = new ApplicationUser
            {
                UserName       = email,
                Email          = email,
                EmailConfirmed = true,
                FirstName      = first,
                LastName       = last,
                DepartmentId   = depts.TryGetValue(dept, out var id) ? id : null,
                IsActive       = true,
            };

            var result = await userManager.CreateAsync(user, SeedPassword);
            if (result.Succeeded)
            {
                await userManager.AddToRoleAsync(user, role);
                logger.LogInformation("DbSeeder: usuario {Email} ({Role})", email, role);
            }
            else
            {
                logger.LogWarning("DbSeeder: error creando {Email}: {Errors}",
                    email, string.Join("; ", result.Errors.Select(e => e.Description)));
            }
        }
    }

    // ── Categorías ──────────────────────────────────────────────────────────
    private static async Task<Dictionary<string, int>> SeedCategoriesAsync(
        QualityDMSDbContext db, ILogger logger)
    {
        if (!await db.DocumentCategories.AnyAsync())
        {
            db.DocumentCategories.AddRange(
                new DocumentCategory { Code = "POL", Name = "Políticas",      Description = "Políticas organizacionales", CreatedBy = SeedBy },
                new DocumentCategory { Code = "PRO", Name = "Procedimientos", Description = "Procedimientos operativos",   CreatedBy = SeedBy },
                new DocumentCategory { Code = "INS", Name = "Instructivos",   Description = "Instructivos de trabajo",     CreatedBy = SeedBy },
                new DocumentCategory { Code = "FOR", Name = "Formatos",       Description = "Formatos y plantillas",       CreatedBy = SeedBy }
            );
            await db.SaveChangesAsync();

            // Subcategoría para mostrar jerarquía (ParentCategoryId).
            var procId = await db.DocumentCategories.Where(c => c.Code == "PRO")
                                                    .Select(c => c.CategoryId).FirstAsync();
            db.DocumentCategories.Add(new DocumentCategory
            {
                Code = "PRO-SEG", Name = "Procedimientos de Seguridad",
                Description = "Subcategoría de procedimientos", ParentCategoryId = procId, CreatedBy = SeedBy,
            });
            await db.SaveChangesAsync();
            logger.LogInformation("DbSeeder: categorías sembradas");
        }

        return await db.DocumentCategories.ToDictionaryAsync(c => c.Name, c => c.CategoryId);
    }

    // ── Flujo de aprobación ───────────────────────────────────────────────────
    private static async Task<WorkflowTemplate> SeedWorkflowAsync(
        QualityDMSDbContext db, ILogger logger)
    {
        var existing = await db.WorkflowTemplates.Include(t => t.Steps).FirstOrDefaultAsync();
        if (existing is not null) return existing;

        var template = new WorkflowTemplate
        {
            Name        = "Flujo de Aprobación de Calidad",
            Description = "Revisión técnica y aprobación final por gerencia de calidad",
            IsActive    = true,
            CreatedBy   = SeedBy,
            Steps =
            {
                new WorkflowStep { StepOrder = 1, StepName = "Revisión Técnica",  AssignedRoleName = RoleApprover,       CreatedBy = SeedBy },
                new WorkflowStep { StepOrder = 2, StepName = "Aprobación Final",   AssignedRoleName = RoleQualityManager, CreatedBy = SeedBy },
            },
        };

        db.WorkflowTemplates.Add(template);
        await db.SaveChangesAsync();
        logger.LogInformation("DbSeeder: plantilla de flujo con {Count} pasos", template.Steps.Count);
        return template;
    }

    // ── Documentos + versiones + estados + flujo ───────────────────────────────
    private static async Task SeedDocumentsAsync(
        QualityDMSDbContext db,
        UserManager<ApplicationUser> userManager,
        Dictionary<string, int> depts,
        Dictionary<string, int> cats,
        WorkflowTemplate template,
        ILogger logger)
    {
        if (await db.Documents.AnyAsync()) return;

        var admin     = await userManager.FindByEmailAsync("admin@qualitydms.local");
        var autor     = await userManager.FindByEmailAsync("autor@qualitydms.local");
        var aprobador = await userManager.FindByEmailAsync("aprobador1@qualitydms.local");
        var gerente   = await userManager.FindByEmailAsync("calidad@qualitydms.local");
        var authorId  = autor?.Id ?? admin!.Id;

        // 1) Documento APROBADO (CurrentStatus = Approved) con versión vigente y flujo completo.
        var pol = Document.Create("POL-001", "Política de Calidad",
            cats["Políticas"], depts["Calidad"], authorId);
        pol.Description = "Política general del sistema de gestión de calidad";
        pol.WorkflowTemplateId = template.WorkflowTemplateId;
        pol.SubmitForApproval();
        pol.Approve(gerente!.Id);
        pol.ClearDomainEvents();
        db.Documents.Add(pol);
        await db.SaveChangesAsync();

        db.DocumentVersions.Add(DocumentVersion.Create(
            pol.DocumentId, "1.0", "seed/POL-001-v1.pdf", "POL-001-v1.pdf",
            0, "application/pdf", authorId, "Versión inicial"));

        // Flujo completado (aprobado) con una acción de aprobación por paso.
        db.WorkflowInstances.Add(new WorkflowInstance
        {
            DocumentId         = pol.DocumentId,
            WorkflowTemplateId = template.WorkflowTemplateId,
            CurrentStepOrder   = 2,
            Status             = WorkflowStepStatus.Approved,
            CompletedAt        = DateTime.UtcNow,
            CreatedBy          = SeedBy,
            Actions =
            {
                new WorkflowAction { StepOrder = 1, ActionByUserId = aprobador!.Id, Action = WorkflowStepStatus.Approved, Comments = "Revisión técnica conforme", ActionDate = DateTime.UtcNow, CreatedBy = SeedBy },
                new WorkflowAction { StepOrder = 2, ActionByUserId = gerente.Id,    Action = WorkflowStepStatus.Approved, Comments = "Aprobado",                  ActionDate = DateTime.UtcNow, CreatedBy = SeedBy },
            },
        });
        await db.SaveChangesAsync();

        // 2) Documento EN REVISIÓN (CurrentStatus = PendingApproval), flujo pendiente en paso 1.
        var pro = Document.Create("PRO-001", "Procedimiento de Control de Documentos",
            cats["Procedimientos"], depts["Calidad"], authorId);
        pro.Description = "Procedimiento para creación, revisión y aprobación de documentos";
        pro.WorkflowTemplateId = template.WorkflowTemplateId;
        pro.SubmitForApproval();
        pro.ClearDomainEvents();
        db.Documents.Add(pro);
        await db.SaveChangesAsync();

        db.DocumentVersions.Add(DocumentVersion.Create(
            pro.DocumentId, "1.0", "seed/PRO-001-v1.pdf", "PRO-001-v1.pdf",
            0, "application/pdf", authorId, "Versión inicial"));
        db.WorkflowInstances.Add(new WorkflowInstance
        {
            DocumentId         = pro.DocumentId,
            WorkflowTemplateId = template.WorkflowTemplateId,
            CurrentStepOrder   = 1,
            Status             = WorkflowStepStatus.InProgress,
            CreatedBy          = SeedBy,
        });
        await db.SaveChangesAsync();

        // 3) Documento BORRADOR (CurrentStatus = Draft).
        var ins = Document.Create("INS-001", "Instructivo de Respaldos",
            cats["Instructivos"], depts["Tecnología"], authorId);
        ins.Description = "Instructivo para respaldo de información en TI";
        ins.ClearDomainEvents();
        db.Documents.Add(ins);
        await db.SaveChangesAsync();

        db.DocumentVersions.Add(DocumentVersion.Create(
            ins.DocumentId, "0.1", "seed/INS-001-v0.1.pdf", "INS-001-v0.1.pdf",
            0, "application/pdf", authorId, "Borrador inicial"));
        await db.SaveChangesAsync();

        logger.LogInformation("DbSeeder: 3 documentos (Approved / PendingApproval / Draft) con versiones y flujo");
    }
}
