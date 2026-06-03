using Bogus;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using QualityDMS.Domain.Entities;
using QualityDMS.Domain.Enums;
using QualityDMS.Domain.Interfaces;
using QualityDMS.Infrastructure.Identity;
using System.Diagnostics;

namespace QualityDMS.Infrastructure.Persistence;

public static class DbSeeder
{
    public const string RoleSuperAdmin     = "SuperAdmin";
    public const string RoleCompanyAdmin   = "AdminEmpresa";
    public const string RoleAdmin          = "Admin";
    public const string RoleQualityManager = "QualityManager";
    public const string RoleApprover       = "Approver";
    public const string RoleAuthor         = "Author";
    public const string RoleViewer         = "Viewer";

    private const string SeedPassword = "Calidad#2026Dev";
    private const string SeedBy       = "seed";

    // ── Punto de entrada: datos base (siempre) ───────────────────────────────
    public static async Task SeedAsync(IServiceProvider services)
    {
        var logger      = services.GetRequiredService<ILogger<QualityDMSDbContext>>();
        var db          = services.GetRequiredService<QualityDMSDbContext>();
        var roleManager = services.GetRequiredService<RoleManager<IdentityRole>>();
        var userManager = services.GetRequiredService<UserManager<ApplicationUser>>();

        await SeedRolesAsync(roleManager, logger);
        var companies = await SeedCompaniesAsync(db, logger);
        var acme = companies["ACME"];
        var beta = companies["BETA"];
        var depts    = await SeedDepartmentsAsync(db, acme, logger);
        await SeedUsersAsync(userManager, acme, beta, depts, logger);
        var cats     = await SeedCategoriesAsync(db, acme, logger);
        var template = await SeedWorkflowAsync(db, acme, logger);
        await SeedDocumentsAsync(db, userManager, acme, depts, cats, template, logger);

        logger.LogInformation("DbSeeder: datos base listos.");
    }

    // ── Punto de entrada: 10,000 documentos sandbox ──────────────────────────
    public static async Task SeedSandboxAsync(IServiceProvider services)
    {
        var logger  = services.GetRequiredService<ILogger<QualityDMSDbContext>>();
        var db      = services.GetRequiredService<QualityDMSDbContext>();
        var config  = services.GetRequiredService<IConfiguration>();

        var sw = Stopwatch.StartNew();
        List<ApprovedDocInfo> approvedSnapshot;

        // ── SQL Server: sembrar solo si no hay datos ──────────────────────────
        if (await db.Documents.CountAsync() > 20)
        {
            logger.LogInformation("DbSeeder sandbox: SQL ya sembrado — reconstruyendo snapshot para verificar APIs.");
            approvedSnapshot = await BuildApprovedSnapshotFromDbAsync(db);
        }
        else
        {
            approvedSnapshot = await SeedSqlServerAsync(db, logger, sw);
        }

        // ── Esperar que PHP y FastAPI estén listos ────────────────────────────
        await WaitForServicesAsync(config, logger);

        // ── Verificar si PHP ya tiene datos (evita push innecesario) ─────────
        var phpUrl = config["PublicDms:PhpSyncUrl"] ?? "http://dms_nginx/php";
        bool phpNeedsData = await PhpIsEmptyAsync(phpUrl, logger);

        if (!phpNeedsData)
        {
            logger.LogInformation("DbSeeder sandbox: PHP ya tiene documentos — omitiendo push.");
            return;
        }

        // ── Propagar documentos aprobados a PHP y FastAPI ─────────────────────
        logger.LogInformation("DbSeeder sandbox: PHP vacío — propagando {Count} docs aprobados...",
            approvedSnapshot.Count);

        var phpSync = services.GetRequiredService<IPhpSyncService>();
        var webhook = services.GetRequiredService<IPublicDmsWebhookService>();

        const int Concurrency = 10;
        int apiSuccess = 0, apiFail = 0;

        await Parallel.ForEachAsync(approvedSnapshot, new ParallelOptions { MaxDegreeOfParallelism = Concurrency },
            async (info, ct) =>
            {
                try
                {
                    await phpSync.ApproveDocumentAsync(
                        info.Doc.DocumentId, info.Doc.Code, info.Doc.Title,
                        info.CategoryId, info.CategoryName,
                        info.DepartmentId, info.DepartmentName,
                        info.Version, info.FileUrl, info.EffectiveDate, null, info.EffectiveDate,
                        info.CompanyId, info.CompanyName);

                    await webhook.NotifyDocumentApprovedAsync(
                        info.Doc.DocumentId, info.Doc.Code, info.Doc.Title,
                        info.CategoryName, info.DepartmentName,
                        info.Version, info.FileUrl, info.CompanyId, info.CompanyName);

                    Interlocked.Increment(ref apiSuccess);
                }
                catch (Exception ex)
                {
                    Interlocked.Increment(ref apiFail);
                    logger.LogWarning("[Seed] Doc {Id} ({Code}) → API error: {Msg}",
                        info.Doc.DocumentId, info.Doc.Code, ex.Message);
                }
            });

        logger.LogInformation(
            "DbSeeder sandbox: completo en {Elapsed}s — {Ok} docs propagados, {Fail} fallos de API.",
            (int)sw.Elapsed.TotalSeconds, apiSuccess, apiFail);
    }

    // ── Siembra los 10,000 docs en SQL Server y devuelve los aprobados ────────
    private static async Task<List<ApprovedDocInfo>> SeedSqlServerAsync(
        QualityDMSDbContext db, ILogger logger, Stopwatch sw)
    {
        const int Total     = 10_000;
        const int BatchSize = 500;

        logger.LogInformation("DbSeeder sandbox: generando {Total} documentos...", Total);

        var acme  = await db.Companies.FirstAsync(c => c.Code == "ACME");
        var cats  = await db.DocumentCategories.Where(c => c.CompanyId == acme.CompanyId).ToListAsync();
        var depts = await db.Departments.Where(d => d.CompanyId == acme.CompanyId).ToListAsync();
        var autor   = await db.Users.FirstAsync(u => u.Email == "autor@qualitydms.local");
        var gerente = await db.Users.FirstAsync(u => u.Email == "calidad@qualitydms.local");

        var faker = new Faker("es");
        var now   = DateTime.UtcNow;
        var approvedSnapshot = new List<ApprovedDocInfo>();

        for (int batch = 0; batch < Total / BatchSize; batch++)
        {
            var docs = new List<Document>(BatchSize);

            for (int i = 0; i < BatchSize; i++)
            {
                int idx  = batch * BatchSize + i + 1;
                var cat  = faker.Random.ArrayElement(cats.ToArray());
                var dept = faker.Random.ArrayElement(depts.ToArray());
                var code = $"{cat.Code.Split('-')[0]}-{idx:D5}";

                var doc = Document.Create(code, BuildTitle(faker, cat.Code, dept.Name),
                    cat.CategoryId, dept.DepartmentId, autor.Id, acme.CompanyId);
                doc.Description = faker.Lorem.Sentence(faker.Random.Int(6, 14));
                doc.ClearDomainEvents();

                // 70 % aprobado · 20 % en revisión · 10 % borrador
                int roll = idx % 10;
                if (roll < 7)
                {
                    var effective = now.AddDays(-faker.Random.Int(1, 365));
                    var fileUrl   = $"seed/{code}-v1.pdf";
                    doc.AddVersion(new DocumentVersion
                    {
                        VersionNumber = "0.1", IsCurrent = false, Status = VersionStatus.Draft,
                        FilePath = $"seed/{code}-v0.1.pdf", FileName = $"{code}-v0.1.pdf",
                        FileSizeBytes = 0, ContentType = "application/pdf",
                        ChangeLog = "Borrador inicial (seed)", CreatedBy = autor.Id,
                    });
                    doc.AddVersion(new DocumentVersion
                    {
                        VersionNumber = "1.0", IsCurrent = true, Status = VersionStatus.Approved,
                        FilePath = fileUrl, FileName = $"{code}-v1.pdf",
                        FileSizeBytes = 0, ContentType = "application/pdf",
                        ChangeLog = "Versión aprobada (seed)",
                        ApprovedBy = gerente.Id, ApprovedAt = effective,
                        CreatedBy = gerente.Id,
                    });
                    doc.RecalculateStatus();
                    approvedSnapshot.Add(new ApprovedDocInfo(
                        doc, cat.CategoryId, cat.Name, dept.DepartmentId, dept.Name,
                        acme.CompanyId, acme.Name, "1.0", fileUrl, effective));
                }
                else if (roll < 9)
                {
                    doc.AddVersion(new DocumentVersion
                    {
                        VersionNumber = "0.1", IsCurrent = false, Status = VersionStatus.PendingApproval,
                        FilePath = $"seed/{code}-v0.1.pdf", FileName = $"{code}-v0.1.pdf",
                        FileSizeBytes = 0, ContentType = "application/pdf",
                        ChangeLog = "En revisión (seed)", CreatedBy = autor.Id,
                    });
                    doc.RecalculateStatus();
                }
                else
                {
                    doc.AddVersion(new DocumentVersion
                    {
                        VersionNumber = "0.1", IsCurrent = false, Status = VersionStatus.Draft,
                        FilePath = $"seed/{code}-v0.1.pdf", FileName = $"{code}-v0.1.pdf",
                        FileSizeBytes = 0, ContentType = "application/pdf",
                        ChangeLog = "Borrador inicial (seed)", CreatedBy = autor.Id,
                    });
                    doc.RecalculateStatus();
                }

                docs.Add(doc);
            }

            db.Documents.AddRange(docs);
            await db.SaveChangesAsync();
            logger.LogInformation("DbSeeder sandbox: lote {Batch}/{Total} → SQL Server ({Elapsed}s)",
                batch + 1, Total / BatchSize, (int)sw.Elapsed.TotalSeconds);
        }

        logger.LogInformation("DbSeeder sandbox: {Count} docs insertados en SQL Server en {Elapsed}s.",
            Total, (int)sw.Elapsed.TotalSeconds);

        return approvedSnapshot;
    }

    // ── Reconstruye el snapshot de aprobados desde SQL Server existente ───────
    private static async Task<List<ApprovedDocInfo>> BuildApprovedSnapshotFromDbAsync(QualityDMSDbContext db)
    {
        var approved = await db.Documents
            .AsNoTracking()
            .Include(d => d.Company)
            .Include(d => d.Category)
            .Include(d => d.Department)
            .Include(d => d.Versions)
            .Where(d => d.Status == DocumentStatus.Approved)
            .ToListAsync();

        return approved
            .Select(doc =>
            {
                var ver = doc.Versions.FirstOrDefault(v => v.IsCurrent && v.Status == VersionStatus.Approved);
                if (ver is null) return null;
                return new ApprovedDocInfo(
                    doc,
                    doc.CategoryId,  doc.Category?.Name  ?? "Unknown",
                    doc.DepartmentId, doc.Department?.Name ?? "Unknown",
                    doc.CompanyId,   doc.Company?.Name   ?? string.Empty,
                    ver.VersionNumber,
                    ver.FilePath ?? string.Empty,
                    ver.ApprovedAt ?? DateTime.UtcNow);
            })
            .Where(x => x is not null)
            .Cast<ApprovedDocInfo>()
            .ToList();
    }

    // ── Devuelve true si PHP/PostgreSQL no tiene documentos activos ───────────
    private static async Task<bool> PhpIsEmptyAsync(string phpBaseUrl, ILogger logger)
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var url = $"{phpBaseUrl.TrimEnd('/')}/api/documents/documents.php?limit=1";
            var resp = await http.GetStringAsync(url);
            var json = System.Text.Json.JsonDocument.Parse(resp);
            var total = json.RootElement
                .GetProperty("pagination")
                .GetProperty("total")
                .GetInt32();
            return total == 0;
        }
        catch (Exception ex)
        {
            logger.LogWarning("[Seed] No se pudo verificar conteo en PHP: {Msg} — asumiendo vacío.", ex.Message);
            return true;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private record ApprovedDocInfo(
        Document Doc,
        int CategoryId, string CategoryName,
        int DepartmentId, string DepartmentName,
        int CompanyId, string CompanyName,
        string Version, string FileUrl, DateTime EffectiveDate);

    private static string BuildTitle(Faker faker, string catCode, string deptName)
    {
        string[] topics =
        [
            "Calidad", "Seguridad Industrial", "Gestión de Riesgos",
            "Control de Documentos", "Capacitación del Personal",
            "Auditoría Interna", "Control de Proveedores",
            "No Conformidades", "Mejora Continua", "Control de Equipos",
            "Gestión Ambiental", "Salud Ocupacional", "Control de Cambios",
            "Gestión de Proyectos", "Control de Registros",
            "Evaluación de Desempeño", "Comunicación Interna",
            "Gestión de Clientes", "Control de Producción", "Mantenimiento Preventivo",
            "Gestión de Compras", "Control de Inventarios",
            "Seguridad de la Información", "Gestión de Contratos",
            "Validación de Procesos", "Gestión de Recursos",
            "Planificación Estratégica", "Control de Costos",
            "Gestión de Quejas", "Evaluación de Proveedores",
            "Equipos de Medición", "Gestión de Competencias",
            "Análisis de Datos", "Revisión por la Dirección", "Trazabilidad",
        ];

        var prefix = catCode.Split('-')[0] switch
        {
            "POL" => "Política",
            "PRO" => "Procedimiento",
            "INS" => "Instructivo",
            "FOR" => "Formato",
            _     => "Documento",
        };

        var topic = faker.Random.ArrayElement(topics);
        return faker.Random.Bool(0.35f)
            ? $"{prefix} de {topic} — {deptName}"
            : $"{prefix} de {topic}";
    }

    private static async Task WaitForServicesAsync(IConfiguration config, ILogger logger)
    {
        var fastapiUrl = config["PublicDms:WebhookUrl"] ?? "http://dms_fastapi:8000";
        var phpUrl     = config["PublicDms:PhpSyncUrl"] ?? "http://dms_nginx";

        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
        await PollUntilReachableAsync(http, $"{fastapiUrl}/health", "FastAPI", logger);
        await PollUntilReachableAsync(http, phpUrl, "PHP",           logger);
    }

    private static async Task PollUntilReachableAsync(
        HttpClient http, string url, string name, ILogger logger, int maxSecs = 90)
    {
        var sw = Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < maxSecs)
        {
            try
            {
                var r = await http.GetAsync(url);
                if ((int)r.StatusCode < 500)
                {
                    logger.LogInformation("DbSeeder: {Name} listo ({Elapsed}s)", name, (int)sw.Elapsed.TotalSeconds);
                    return;
                }
            }
            catch { /* todavía arrancando */ }

            await Task.Delay(3_000);
        }
        logger.LogWarning("DbSeeder: {Name} no respondió en {Max}s — las llamadas API pueden fallar.", name, maxSecs);
    }

    // ── Datos base ────────────────────────────────────────────────────────────

    private static async Task<Dictionary<string, int>> SeedCompaniesAsync(
        QualityDMSDbContext db, ILogger logger)
    {
        if (!await db.Companies.AnyAsync())
        {
            db.Companies.AddRange(
                new Company { Code = "ACME", Name = "ACME Corporation", TaxId = "ACME-900100", CreatedBy = SeedBy },
                new Company { Code = "BETA", Name = "Beta Industries",   TaxId = "BETA-900200", CreatedBy = SeedBy }
            );
            await db.SaveChangesAsync();
            logger.LogInformation("DbSeeder: empresas sembradas (ACME, BETA)");
        }
        return await db.Companies.ToDictionaryAsync(c => c.Code, c => c.CompanyId);
    }

    private static async Task SeedRolesAsync(RoleManager<IdentityRole> roleManager, ILogger logger)
    {
        string[] roles = [RoleSuperAdmin, RoleCompanyAdmin, RoleAdmin, RoleQualityManager, RoleApprover, RoleAuthor, RoleViewer];
        foreach (var role in roles)
        {
            if (!await roleManager.RoleExistsAsync(role))
            {
                await roleManager.CreateAsync(new IdentityRole(role));
                logger.LogInformation("DbSeeder: rol creado {Role}", role);
            }
        }
    }

    private static async Task<Dictionary<string, int>> SeedDepartmentsAsync(
        QualityDMSDbContext db, int companyId, ILogger logger)
    {
        if (!await db.Departments.AnyAsync(d => d.CompanyId == companyId))
        {
            db.Departments.AddRange(
                new Department { CompanyId = companyId, Code = "CAL",  Name = "Calidad",          Description = "Gestión de calidad y mejora continua", ManagerName = "Gerente de Calidad", CreatedBy = SeedBy },
                new Department { CompanyId = companyId, Code = "OPE",  Name = "Operaciones",      Description = "Operación y producción",                CreatedBy = SeedBy },
                new Department { CompanyId = companyId, Code = "RRHH", Name = "Recursos Humanos", Description = "Gestión del personal",                  CreatedBy = SeedBy },
                new Department { CompanyId = companyId, Code = "TI",   Name = "Tecnología",       Description = "Sistemas e infraestructura",            CreatedBy = SeedBy }
            );
            await db.SaveChangesAsync();
            logger.LogInformation("DbSeeder: departamentos sembrados");
        }
        return await db.Departments.Where(d => d.CompanyId == companyId)
                                    .ToDictionaryAsync(d => d.Name, d => d.DepartmentId);
    }

    private static async Task SeedUsersAsync(
        UserManager<ApplicationUser> userManager, int acmeId, int betaId,
        Dictionary<string, int> depts, ILogger logger)
    {
        (string Email, string First, string Last, string Dept, string Role, int? Company)[] users =
        [
            ("super@qualitydms.local",       "Super",          "Admin",        "",                 RoleSuperAdmin,     null),
            ("admin@qualitydms.local",       "Administrador",  "del Sistema",  "Calidad",          RoleAdmin,          acmeId),
            ("adminempresa@qualitydms.local","Admin",           "ACME",         "Calidad",          RoleCompanyAdmin,   acmeId),
            ("calidad@qualitydms.local",     "Gerente",        "de Calidad",   "Calidad",          RoleQualityManager, acmeId),
            ("aprobador1@qualitydms.local",  "Juan",           "Pérez",        "Calidad",          RoleApprover,       acmeId),
            ("aprobador2@qualitydms.local",  "María",          "García",       "Operaciones",      RoleApprover,       acmeId),
            ("autor@qualitydms.local",       "Carlos",         "López",        "Operaciones",      RoleAuthor,         acmeId),
            ("lector@qualitydms.local",      "Ana",            "Torres",       "Recursos Humanos", RoleViewer,         acmeId),
            ("admin.beta@qualitydms.local",  "Admin",          "Beta",         "",                 RoleCompanyAdmin,   betaId),
        ];

        foreach (var (email, first, last, dept, role, company) in users)
        {
            if (await userManager.FindByEmailAsync(email) is not null) continue;

            var user = new ApplicationUser
            {
                UserName       = email,
                Email          = email,
                EmailConfirmed = true,
                FirstName      = first,
                LastName       = last,
                CompanyId      = company,
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

    private static async Task<Dictionary<string, int>> SeedCategoriesAsync(
        QualityDMSDbContext db, int companyId, ILogger logger)
    {
        if (!await db.DocumentCategories.AnyAsync(c => c.CompanyId == companyId))
        {
            db.DocumentCategories.AddRange(
                new DocumentCategory { CompanyId = companyId, Code = "POL", Name = "Políticas",      Description = "Políticas organizacionales", CreatedBy = SeedBy },
                new DocumentCategory { CompanyId = companyId, Code = "PRO", Name = "Procedimientos", Description = "Procedimientos operativos",   CreatedBy = SeedBy },
                new DocumentCategory { CompanyId = companyId, Code = "INS", Name = "Instructivos",   Description = "Instructivos de trabajo",     CreatedBy = SeedBy },
                new DocumentCategory { CompanyId = companyId, Code = "FOR", Name = "Formatos",       Description = "Formatos y plantillas",       CreatedBy = SeedBy }
            );
            await db.SaveChangesAsync();

            var procId = await db.DocumentCategories.Where(c => c.CompanyId == companyId && c.Code == "PRO")
                                                    .Select(c => c.CategoryId).FirstAsync();
            db.DocumentCategories.Add(new DocumentCategory
            {
                CompanyId = companyId, Code = "PRO-SEG", Name = "Procedimientos de Seguridad",
                Description = "Subcategoría de procedimientos", ParentCategoryId = procId, CreatedBy = SeedBy,
            });
            await db.SaveChangesAsync();
            logger.LogInformation("DbSeeder: categorías sembradas");
        }

        return await db.DocumentCategories.Where(c => c.CompanyId == companyId)
                                          .ToDictionaryAsync(c => c.Name, c => c.CategoryId);
    }

    private static async Task<WorkflowTemplate> SeedWorkflowAsync(
        QualityDMSDbContext db, int companyId, ILogger logger)
    {
        var existing = await db.WorkflowTemplates.Include(t => t.Steps)
            .FirstOrDefaultAsync(t => t.CompanyId == companyId);
        if (existing is not null) return existing;

        var template = new WorkflowTemplate
        {
            CompanyId   = companyId,
            Name        = "Flujo de Aprobación de Calidad",
            Description = "Revisión técnica y aprobación final por gerencia de calidad",
            IsActive    = true,
            CreatedBy   = SeedBy,
            Steps =
            {
                new WorkflowStep { StepOrder = 1, StepName = "Revisión Técnica", AssignedRoleName = RoleApprover,       CreatedBy = SeedBy },
                new WorkflowStep { StepOrder = 2, StepName = "Aprobación Final", AssignedRoleName = RoleQualityManager, CreatedBy = SeedBy },
            },
        };

        db.WorkflowTemplates.Add(template);
        await db.SaveChangesAsync();
        logger.LogInformation("DbSeeder: plantilla de flujo con {Count} pasos", template.Steps.Count);
        return template;
    }

    private static async Task SeedDocumentsAsync(
        QualityDMSDbContext db,
        UserManager<ApplicationUser> userManager,
        int companyId,
        Dictionary<string, int> depts,
        Dictionary<string, int> cats,
        WorkflowTemplate template,
        ILogger logger)
    {
        if (await db.Documents.AnyAsync(d => d.CompanyId == companyId)) return;

        var admin     = await userManager.FindByEmailAsync("admin@qualitydms.local");
        var autor     = await userManager.FindByEmailAsync("autor@qualitydms.local");
        var aprobador = await userManager.FindByEmailAsync("aprobador1@qualitydms.local");
        var gerente   = await userManager.FindByEmailAsync("calidad@qualitydms.local");
        var authorId  = autor?.Id ?? admin!.Id;
        var now       = DateTime.UtcNow;

        // 1) Aprobado — borrador 0.1 + versión vigente 1.0
        var pol = Document.Create("POL-001", "Política de Calidad",
            cats["Políticas"], depts["Calidad"], authorId, companyId);
        pol.Description = "Política general del sistema de gestión de calidad";
        pol.WorkflowTemplateId = template.WorkflowTemplateId;
        pol.ClearDomainEvents();
        pol.AddVersion(new DocumentVersion { VersionNumber = "0.1", FilePath = "seed/POL-001-v0.1.pdf", FileName = "POL-001-v0.1.pdf", FileSizeBytes = 0, ContentType = "application/pdf", ChangeLog = "Borrador inicial", Status = VersionStatus.Draft, IsCurrent = false, CreatedBy = authorId });
        pol.AddVersion(new DocumentVersion { VersionNumber = "1.0", FilePath = "seed/POL-001-v1.pdf",   FileName = "POL-001-v1.pdf",   FileSizeBytes = 0, ContentType = "application/pdf", ChangeLog = "Versión aprobada", Status = VersionStatus.Approved, IsCurrent = true, ApprovedBy = gerente!.Id, ApprovedAt = now, CreatedBy = gerente.Id });
        pol.RecalculateStatus();
        db.Documents.Add(pol);
        await db.SaveChangesAsync();

        db.WorkflowInstances.Add(new WorkflowInstance
        {
            DocumentId = pol.DocumentId, DocumentVersionId = pol.Versions.First(v => v.VersionNumber == "0.1").VersionId,
            WorkflowTemplateId = template.WorkflowTemplateId, CurrentStepOrder = 2,
            Status = WorkflowStepStatus.Approved, CompletedAt = now, CreatedBy = SeedBy,
            Actions =
            {
                new WorkflowAction { StepOrder = 1, ActionByUserId = aprobador!.Id, Action = WorkflowStepStatus.Approved, Comments = "Revisión técnica conforme", ActionDate = now, CreatedBy = SeedBy },
                new WorkflowAction { StepOrder = 2, ActionByUserId = gerente.Id,    Action = WorkflowStepStatus.Approved, Comments = "Aprobado",                  ActionDate = now, CreatedBy = SeedBy },
            },
        });
        await db.SaveChangesAsync();

        // 2) En revisión — borrador 0.1 en PendingApproval
        var pro = Document.Create("PRO-001", "Procedimiento de Control de Documentos",
            cats["Procedimientos"], depts["Calidad"], authorId, companyId);
        pro.Description = "Procedimiento para creación, revisión y aprobación de documentos";
        pro.WorkflowTemplateId = template.WorkflowTemplateId;
        pro.ClearDomainEvents();
        pro.AddVersion(new DocumentVersion { VersionNumber = "0.1", FilePath = "seed/PRO-001-v0.1.pdf", FileName = "PRO-001-v0.1.pdf", FileSizeBytes = 0, ContentType = "application/pdf", ChangeLog = "Borrador inicial", Status = VersionStatus.PendingApproval, IsCurrent = false, CreatedBy = authorId });
        pro.RecalculateStatus();
        db.Documents.Add(pro);
        await db.SaveChangesAsync();

        db.WorkflowInstances.Add(new WorkflowInstance
        {
            DocumentId = pro.DocumentId, DocumentVersionId = pro.Versions.First().VersionId,
            WorkflowTemplateId = template.WorkflowTemplateId, CurrentStepOrder = 1,
            Status = WorkflowStepStatus.InProgress, CreatedBy = SeedBy,
        });
        await db.SaveChangesAsync();

        // 3) Borrador puro
        var ins = Document.Create("INS-001", "Instructivo de Respaldos",
            cats["Instructivos"], depts["Tecnología"], authorId, companyId);
        ins.Description = "Instructivo para respaldo de información en TI";
        ins.ClearDomainEvents();
        ins.AddVersion(new DocumentVersion { VersionNumber = "0.1", FilePath = "seed/INS-001-v0.1.pdf", FileName = "INS-001-v0.1.pdf", FileSizeBytes = 0, ContentType = "application/pdf", ChangeLog = "Borrador inicial", Status = VersionStatus.Draft, IsCurrent = false, CreatedBy = authorId });
        ins.RecalculateStatus();
        db.Documents.Add(ins);
        await db.SaveChangesAsync();

        logger.LogInformation("DbSeeder: 3 documentos base (Approved / PendingApproval / Draft)");
    }
}
