<div align="center">

<img src="../assets/git-swapping-mark.svg" width="96" height="96" alt="Símbolo de dos perfiles de Git Swapping" />

# Git Swapping

[English](../../README.md) · **Español** · [Italiano](../it/README.md)

**Cada repositorio, con su cuenta.**

Perfiles de Git por repositorio desde PowerShell.

[![v0.1.0-alpha.2](https://img.shields.io/badge/release-v0.1.0--alpha.2-256b56?style=flat-square)](../releases/v0.1.0-alpha.2.md) [![CI](https://github.com/karatekah/git-swapping/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/karatekah/git-swapping/actions/workflows/ci.yml) [![Windows](https://img.shields.io/badge/plataforma-Windows-64748b?style=flat-square)](#requisitos)

[Inicio rápido](#inicio-rápido) · [Comandos](#comandos) · [Notas de la alfa](../releases/v0.1.0-alpha.2.md) · [Reportar un error](https://github.com/karatekah/git-swapping/issues)

</div>

---

Asigna un perfil una vez y trabaja en cada proyecto con su identidad local. **Alfa experimental:** una cuenta GitHub por propietario, remotes HTTPS y verificaciones explícitas.

## Qué incluye la alfa

- Identidad local mediante `user.name` y `user.email`, conservando la configuración global.
- Validación del propietario antes de aplicar un perfil: los proyectos personales y universitarios permanecen separados.
- Comprobación de las URLs de descarga y envío; se actualiza también un `pushurl` explícito. Ambas deben apuntar al mismo repositorio.
- Escrituras preparadas bajo bloqueo y sustitución atómica de la configuración, evitando cambios parciales.
- Errores reales ante fallos de Git, remotes ausentes, URLs incompatibles o identidades que no coinciden.
- Datos reales en `profiles.psd1`, excluido de Git. Solo se publica una plantilla.

## Requisitos

Windows PowerShell 5.1 o PowerShell 7 en Windows; Git 2.31 o posterior en `PATH`; autenticación HTTPS ya configurada, por ejemplo con Git Credential Manager.

Se admite un repositorio de trabajo normal con una URL de descarga en `origin` y como máximo una URL explícita de envío. Esta alfa no admite SSH, repositorios bare, GitHub Enterprise, múltiples URLs ni archivos de configuración que sean enlaces. La sustitución atómica requiere un sistema de archivos local compatible.

## Inicio rápido

En una copia recién clonada:

```powershell
git clone https://github.com/karatekah/git-swapping.git
cd git-swapping
.\install.ps1
git-profile list
```

El instalador pide una etiqueta, el nombre y correo para los commits y el usuario de GitHub por cada perfil. Puedes usar etiquetas como `personal` o `trabajo`. El usuario de GitHub debe coincidir con el propietario del repositorio. Puedes usar un correo `noreply` de GitHub para tus commits.

El comando queda disponible en la sesión actual y en futuras sesiones del mismo host de PowerShell. Ejecuta el instalador en cada edición o host que uses. Si ya existe `profiles.psd1`, reutiliza las cuentas y crea un respaldo del perfil de PowerShell antes de modificarlo.

Dentro de un proyecto personal:

```powershell
cd C:\ruta\proyecto-personal
git-profile use personal
git-profile status
git fetch origin
```

Para otra cuenta, usa la etiqueta que le asignaste, por ejemplo `git-profile use trabajo`. Cada repositorio conserva su configuración al cambiar de carpeta.

## Comandos

| Comando | Función |
| --- | --- |
| `git-profile` o `git-profile help` | Mostrar uso y versión |
| `git-profile list` | Listar perfiles, incluso fuera de un repositorio |
| `git-profile add PERFIL` | Crear un perfil con la identidad para los commits y el usuario de GitHub |
| `git-profile edit PERFIL` | Editar un perfil guardado. Pulsa Enter para conservar el valor de un campo |
| `git-profile remove PERFIL` | Eliminar un perfil guardado tras confirmarlo |
| `git-profile current` | Mostrar la identidad local y las URLs efectivas de descarga y envío de `origin` |
| `git-profile use PERFIL` | Validar propietario y aplicar identidad y URLs locales |
| `git-profile check` | Comprobar el perfil, el propietario y las URLs de `origin`, el remoto de envío predeterminado y las identidades efectivas de autor y committer |
| `git-profile status` | Mostrar el estado y el remoto de envío predeterminado, y ejecutar la misma comprobación |

Ejecuta `list`, `add`, `edit` o `remove` desde cualquier carpeta. Estos comandos administran las cuentas de tu archivo local `profiles.psd1`. Para aplicar una identidad editada, ejecuta `git-profile use PERFIL` dentro del repositorio. Escribe `y` para confirmar una eliminación o pulsa Enter para cancelarla. Si la lista queda vacía, puedes volver a crear un perfil con `add`.

Los errores lanzan excepciones de PowerShell, capturables con `try` / `catch`. La función no cierra tu terminal. `use` confirma que se guardó la configuración; ejecuta `check` para detectar otras opciones que sobrescriban la identidad.

Si `git push` sin argumentos selecciona un destino distinto de `origin`, `check` y `status` indican qué ajuste de Git lo seleccionó. Esta comprobación se ejecuta sin conexión.

## Identidad y autenticación

El autor del commit, el usuario de la URL y la credencial de autenticación son datos distintos. `check` funciona sin red y no comprueba permisos remotos. Un fetch correcto demuestra acceso de lectura; no demuestra permisos de envío ni identifica la credencial utilizada.

La herramienta conserva las credenciales existentes y la configuración global, y no cambia la cuenta activa de `gh`. Los commits anteriores mantienen sus metadatos; configurar `noreply` protege los commits nuevos.

## Arquitectura y desarrollo

| Parte | Implementación |
| --- | --- |
| CLI | Función de `git-profile.ps1`, cargada desde `$PROFILE` |
| Instalación | `install.ps1` configura las cuentas y registra la función |
| Cuentas | Archivo de datos local `profiles.psd1` |
| Configuración | Git instalado, códigos de salida comprobados y sustitución atómica |
| Pruebas | Repositorios temporales reales, sin red ni credenciales guardadas |
| CI | GitHub Actions en Windows PowerShell 5.1 y PowerShell 7 |

Sin instalar dependencias:

```powershell
powershell -NoProfile -File .\tests\git-profile.Tests.ps1
# Si tienes PowerShell 7:
pwsh -NoProfile -File .\tests\git-profile.Tests.ps1
```

Las pruebas cubren ambos perfiles, repetición, propietario incorrecto, URLs independientes de envío, bloqueos, escrituras fallidas y otras identidades que sobrescriben el perfil.

## Documentación y próximos pasos

- [Alcance y verificación de la alfa](../releases/v0.1.0-alpha.2.md) · [Changelog](../../CHANGELOG.md).
- Próximos pasos: uso en más equipos Windows y mapeos de propietarios más flexibles. SSH y otros proveedores requieren un diseño de autenticación propio.

Si mueves o renombras la copia, ejecuta `install.ps1` desde su nueva ubicación. Respalda `profiles.psd1` antes de eliminar la copia, ya que Git excluye ese archivo.

---

[Made by Karatekah](https://github.com/karatekah)
