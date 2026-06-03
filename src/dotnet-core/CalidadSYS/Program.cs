using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using QualityDMS.Application;
using QualityDMS.Application.Common.Exceptions;
using QualityDMS.Infrastructure;
using QualityDMS.Infrastructure.Persistence;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);

// Persiste las claves Data Protection para que los tokens de antiforgery y las cookies
// de autenticación sobrevivan reinicios del contenedor.
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo("/app/dp-keys"))
    .SetApplicationName("QualityDMS");

builder.Services.ConfigureApplicationCookie(opts =>
{
    opts.LoginPath = "/Account/Login";
    opts.LogoutPath = "/Account/Logout";
    opts.AccessDeniedPath = "/Account/AccessDenied";
    opts.ExpireTimeSpan = TimeSpan.FromHours(8);
    opts.SlidingExpiration = true;
    opts.Cookie.Name = "QualityDMS.Auth";
});

builder.Services.AddAuthentication()
    .AddJwtBearer(JwtBearerDefaults.AuthenticationScheme, opts =>
    {
        opts.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Secret"]!)),
            ValidateIssuer = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidateAudience = true,
            ValidAudience = builder.Configuration["Jwt:Audience"],
            ValidateLifetime = true,
            ClockSkew = TimeSpan.Zero
        };
    });

builder.Services.AddAuthorization(opts =>
{
    opts.AddPolicy("CanApproveDocuments",
        p => p.RequireRole("Approver", "Manager", "QualityManager", "Admin"));
    opts.AddPolicy("CanManageWorkflows",
        p => p.RequireRole("QualityManager", "Admin"));
    opts.AddPolicy("ApiPolicy",
        p => p.AddAuthenticationSchemes(JwtBearerDefaults.AuthenticationScheme)
              .RequireAuthenticatedUser());
});

builder.Services.AddControllersWithViews();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(opts =>
{
    opts.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "QualityDMS API",
        Version = "v1",
        Description = "Sistema de Gestión Documental de Calidad - ISO 9001:2015"
    });
    opts.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT"
    });
    opts.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
            },
            Array.Empty<string>()
        }
    });
});

builder.Services.AddResponseCaching();

var app = builder.Build();

// Detrás de Nginx con routing por path (/dotnet): respeta el prefijo público.
// Tag helpers, cookies y static files usan PathBase automáticamente.
// Sin header (acceso directo :5080) → PathBase vacío → funciona igual.
app.Use(async (context, next) =>
{
    var prefix = context.Request.Headers["X-Forwarded-Prefix"].ToString();
    if (!string.IsNullOrEmpty(prefix))
        context.Request.PathBase = new PathString(prefix.TrimEnd('/'));
    await next(context);
});

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "QualityDMS v1"));
}
else
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.Use(async (context, next) =>
{
    try
    {
        await next(context);
    }
    catch (ValidationException ex)
    {
        if (context.Request.Path.StartsWithSegments("/api"))
        {
            context.Response.StatusCode = 400;
            await context.Response.WriteAsJsonAsync(new { errors = ex.Errors });
        }
        else throw;
    }
    catch (NotFoundException ex)
    {
        if (context.Request.Path.StartsWithSegments("/api"))
        {
            context.Response.StatusCode = 404;
            await context.Response.WriteAsJsonAsync(new { error = ex.Message });
        }
        else throw;
    }
});

app.UseResponseCaching();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthentication();
app.UseAuthorization();

app.MapStaticAssets();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Dashboard}/{action=Index}/{id?}")
    .WithStaticAssets();

app.MapControllers();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<QualityDMSDbContext>();
    for (var attempt = 1; attempt <= 10; attempt++)
    {
        try { db.Database.EnsureCreated(); break; }
        catch (Exception ex) when (attempt < 10)
        {
            Console.WriteLine($"[DB] SQL Server not ready (attempt {attempt}/10): {ex.Message}. Retrying in 5s...");
            Thread.Sleep(5000);
        }
    }

    // DMS_SEED_MODE: sandbox → datos base + 10 000 docs | dev → datos base | none → sin seed
    var seedMode = Environment.GetEnvironmentVariable("DMS_SEED_MODE") ?? "dev";
    Console.WriteLine($"[DB] Seed mode: {seedMode}");

    if (seedMode != "none")
    {
        try { await DbSeeder.SeedAsync(scope.ServiceProvider); }
        catch (Exception ex) { Console.WriteLine($"[DB] Seed base falló: {ex.Message}"); }

        if (seedMode == "sandbox")
        {
            try { await DbSeeder.SeedSandboxAsync(scope.ServiceProvider); }
            catch (Exception ex) { Console.WriteLine($"[DB] Seed sandbox falló: {ex.Message}"); }
        }
    }
}

app.Run();
