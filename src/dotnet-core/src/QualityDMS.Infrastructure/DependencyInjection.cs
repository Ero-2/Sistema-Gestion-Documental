using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using QualityDMS.Application.Auth.Commands.Login;
using QualityDMS.Domain.Interfaces;
using QualityDMS.Infrastructure.Identity;
using QualityDMS.Infrastructure.Persistence;
using QualityDMS.Infrastructure.Persistence.Repositories;
using QualityDMS.Infrastructure.Services;
using QualityDMS.Infrastructure.Storage;
using Microsoft.Extensions.Logging;

namespace QualityDMS.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services, IConfiguration configuration)
    {
        services.AddDbContext<QualityDMSDbContext>(opts =>
            opts.UseSqlServer(
                configuration.GetConnectionString("QualityDMS"),
                sql => sql.MigrationsAssembly(typeof(QualityDMSDbContext).Assembly.FullName)));

        services.AddIdentity<ApplicationUser, IdentityRole>(opts =>
        {
            opts.Password.RequiredLength = 12;
            opts.Password.RequireDigit = true;
            opts.Password.RequireUppercase = true;
            opts.Password.RequireNonAlphanumeric = true;
            opts.Lockout.MaxFailedAccessAttempts = 5;
            opts.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(15);
        })
        .AddEntityFrameworkStores<QualityDMSDbContext>()
        .AddDefaultTokenProviders();

        services.AddSingleton<IDocumentSearchService>(sp =>
            new MongoDocumentSearchService(configuration, sp.GetRequiredService<ILogger<MongoDocumentSearchService>>()));
        services.AddScoped<IDocumentRepository, DocumentRepository>();
        services.AddScoped<IWorkflowRepository, WorkflowRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();
        services.AddScoped<ICurrentUserService, CurrentUserService>();
        services.AddScoped<INotificationService, NotificationService>();
        services.AddScoped<IIdentityService, IdentityService>();
        services.AddScoped<ITokenService, TokenService>();

        var storagePath = configuration["Storage:LocalPath"] ?? Path.Combine(Directory.GetCurrentDirectory(), "uploads");
        services.AddSingleton<IFileStorageService>(_ => new LocalFileStorageService(storagePath));

        services.AddHttpContextAccessor();

        var fastapiUrl = configuration["PublicDms:WebhookUrl"] ?? "http://fastapi:8000";
        var fastapiKey  = configuration["PublicDms:ApiKey"] ?? "";
        services.AddHttpClient<IPublicDmsWebhookService, PublicDmsWebhookService>(client =>
        {
            client.BaseAddress = new Uri(fastapiUrl);
            client.Timeout     = TimeSpan.FromSeconds(5);
            if (!string.IsNullOrEmpty(fastapiKey))
                client.DefaultRequestHeaders.Add("X-API-Key", fastapiKey);
        });

        var phpUrl = configuration["PublicDms:PhpSyncUrl"] ?? "http://php";
        var apiKey = configuration["PublicDms:ApiKey"] ?? "";
        services.AddHttpClient<IPhpSyncService, PhpSyncService>(client =>
        {
            client.BaseAddress = new Uri(phpUrl);
            client.Timeout     = TimeSpan.FromSeconds(5);
            if (!string.IsNullOrEmpty(apiKey))
                client.DefaultRequestHeaders.Add("X-API-Key", apiKey);
        });

        return services;
    }
}
