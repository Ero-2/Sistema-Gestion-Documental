using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using QualityDMS.Application.Dashboard.Queries.GetMetrics;
using QualityDMS.Application.Workflow.Queries.GetPendingApprovals;
using QualityDMS.Domain.Interfaces;
using QualityDMS.Infrastructure.Persistence;

namespace CalidadSYS.Controllers;

[Authorize]
public class DashboardController(IMediator mediator, ICurrentUserService currentUser, QualityDMSDbContext db) : Controller
{
    public async Task<IActionResult> Index(CancellationToken ct)
    {
        var metrics = await mediator.Send(new GetDashboardMetricsQuery(), ct);
        var pending = await mediator.Send(new GetPendingApprovalsQuery(currentUser.UserId), ct);

        // Resolver GUIDs de actividad reciente a nombres legibles
        var userIds = metrics.RecentActivity
            .Select(a => a.User)
            .Where(id => !string.IsNullOrWhiteSpace(id) && id != "seed")
            .Distinct()
            .ToList();

        var userNames = await db.Users.IgnoreQueryFilters()
            .Where(u => userIds.Contains(u.Id))
            .Select(u => new { u.Id, u.FirstName, u.LastName, u.UserName })
            .ToDictionaryAsync(u => u.Id, u =>
            {
                var full = $"{u.FirstName} {u.LastName}".Trim();
                return full.Length > 0 ? full : (u.UserName ?? u.Id);
            }, ct);

        userNames["seed"] = "Sistema";

        ViewBag.UserNames = userNames;
        ViewBag.PendingCount = pending.Count();
        ViewData["Title"] = "Dashboard";

        return View(metrics);
    }
}
