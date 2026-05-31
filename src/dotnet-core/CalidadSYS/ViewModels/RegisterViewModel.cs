using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace CalidadSYS.ViewModels;

public class RegisterViewModel
{
    [Required(ErrorMessage = "El nombre es requerido")]
    [StringLength(100)]
    [Display(Name = "Nombre")]
    public string FirstName { get; set; } = string.Empty;

    [Required(ErrorMessage = "El apellido es requerido")]
    [StringLength(100)]
    [Display(Name = "Apellido")]
    public string LastName { get; set; } = string.Empty;

    [Required(ErrorMessage = "El correo es requerido")]
    [EmailAddress(ErrorMessage = "Correo inválido")]
    [Display(Name = "Correo electrónico")]
    public string Email { get; set; } = string.Empty;

    [Required(ErrorMessage = "La contraseña es requerida")]
    [StringLength(100, MinimumLength = 12, ErrorMessage = "Mínimo 12 caracteres")]
    [DataType(DataType.Password)]
    [Display(Name = "Contraseña")]
    public string Password { get; set; } = string.Empty;

    [Required(ErrorMessage = "Confirma la contraseña")]
    [DataType(DataType.Password)]
    [Compare(nameof(Password), ErrorMessage = "Las contraseñas no coinciden")]
    [Display(Name = "Confirmar contraseña")]
    public string ConfirmPassword { get; set; } = string.Empty;

    [Required(ErrorMessage = "Selecciona un rol")]
    [Display(Name = "Tipo de usuario")]
    public string Role { get; set; } = "Viewer";

    [Display(Name = "Empresa")]
    public int? CompanyId { get; set; }

    public bool AdminExists { get; set; }
    public IEnumerable<SelectListItem> Companies { get; set; } = [];
}
