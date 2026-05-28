using MediatR;
using Microsoft.AspNetCore.Mvc;
using QualityDMS.Application.Auth.Commands.Login;
using QualityDMS.Domain.Interfaces;

namespace CalidadSYS.Controllers.Api;

[ApiController]
[Route("api/v1/[controller]")]
public class AuthController(IMediator mediator, IIdentityService identityService) : ControllerBase
{
    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequest req, CancellationToken ct)
    {
        var result = await mediator.Send(new LoginCommand(req.Email, req.Password), ct);
        return result.IsSuccess ? Ok(result.Value) : Unauthorized(result.Error);
    }

    /// <summary>
    /// Validar credenciales para sistemas secundarios (PHP, FastAPI).
    /// Devuelve: userId, userName, email, roles (sin token).
    /// Sistemas secundarios generan sus propios tokens/sesiones.
    /// </summary>
    [HttpPost("validate")]
    [ProducesResponseType(typeof(UserValidationResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> ValidateCredentials([FromBody] LoginRequest req, CancellationToken ct)
    {
        var (success, userId, userName, roles) = await identityService.ValidateCredentialsAsync(
            req.Email, req.Password, ct);

        if (!success)
            return Unauthorized(new { error = "Credenciales inválidas" });

        return Ok(new UserValidationResponse(
            UserId: userId,
            UserName: userName,
            Email: req.Email,
            Roles: roles.ToList()
        ));
    }
}

public record LoginRequest(string Email, string Password);

public record UserValidationResponse(
    string UserId,
    string UserName,
    string Email,
    List<string> Roles
);
