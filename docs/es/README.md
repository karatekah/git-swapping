<div align="center">

<img src="../assets/githubswapping-mark.svg" width="96" height="96" alt="Marca de terminal GithubSwapping" />

# GithubSwapping

[English](../../README.md) · **Español** · [Italiano](../it/README.md)

**Cada repositorio, con su cuenta.**

Una pequeña CLI de PowerShell para separar identidades personales y universitarias de Git por repositorio.

[![v0.1.0-alpha.1](https://img.shields.io/badge/release-v0.1.0--alpha.1-256b56?style=flat-square)](../releases/v0.1.0-alpha.1.md) [![CI](https://github.com/karatekah/GithubSwapping/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/karatekah/GithubSwapping/actions/workflows/ci.yml) [![Windows](https://img.shields.io/badge/plataforma-Windows-64748b?style=flat-square)](#requisitos)

[Inicio rápido](#inicio-rápido) · [Comandos](#comandos) · [Notas de la alfa](../releases/v0.1.0-alpha.1.md) · [Reportar un error](https://github.com/karatekah/GithubSwapping/issues)

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
git clone https://github.com/karatekah/GithubSwapping.git
cd GithubSwapping
Copy-Item .\profiles.example.psd1 .\profiles.psd1
notepad .\profiles.psd1
```

Completa nombres, correos y usuarios GitHub. `personal` y `unsa` son etiquetas: el campo `GitHub` debe coincidir con el propietario del repositorio. Puedes usar el correo `noreply` que ofrece GitHub para proteger tu dirección personal en los nuevos commits.

```powershell
. .\git-profile.ps1
git-profile list
```

Agrega **una sola vez** esta carga a tu `$PROFILE`, reemplazando la ruta por la ubicación absoluta de la copia:

```powershell
if (Test-Path -LiteralPath 'C:\ruta\GithubSwapping\git-profile.ps1') {
    . 'C:\ruta\GithubSwapping\git-profile.ps1'
}
```

Si el perfil o su carpeta no existen, créalos antes de editar. Conserva el resto de su contenido. Windows PowerShell y PowerShell 7 utilizan perfiles diferentes. Reinicia la terminal o ejecuta `. $PROFILE` después del cambio.

Dentro de un proyecto personal:

```powershell
cd C:\ruta\proyecto-personal
git-profile use personal
git-profile status
git fetch origin
```

Para un proyecto de la cuenta universitaria utiliza `git-profile use unsa`. Cada repositorio conserva su configuración al cambiar de carpeta.

## Comandos

| Comando | Función |
| --- | --- |
| `git-profile` o `git-profile help` | Mostrar uso y versión |
| `git-profile list` | Listar perfiles, incluso fuera de un repositorio |
| `git-profile current` | Mostrar identidad local y URLs efectivas de descarga y envío |
| `git-profile use PERFIL` | Validar propietario y aplicar identidad y URLs locales |
| `git-profile check` | Comprobar perfil, propietario, URLs e identidades efectivas de autor y committer |
| `git-profile status` | Mostrar el estado y ejecutar la misma comprobación |

Los errores lanzan excepciones de PowerShell, capturables con `try` / `catch`. La función no cierra tu terminal. `use` confirma que se guardó la configuración; ejecuta `check` para detectar otras opciones que sobrescriban la identidad.

## Identidad y autenticación

El autor del commit, el usuario de la URL y la credencial de autenticación son datos distintos. `check` funciona sin red y no comprueba permisos remotos. Un fetch correcto demuestra acceso de lectura; no demuestra permisos de envío ni identifica la credencial utilizada.

La herramienta conserva las credenciales existentes y la configuración global, y no cambia la cuenta activa de `gh`. Los commits anteriores mantienen sus metadatos; configurar `noreply` protege los commits nuevos.

## Arquitectura y desarrollo

| Parte | Implementación |
| --- | --- |
| CLI | Función de `git-profile.ps1`, cargada desde `$PROFILE` |
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

- [Alcance y verificación de la alfa](../releases/v0.1.0-alpha.1.md) · [Changelog](../../CHANGELOG.md).
- Próximos pasos: uso en más equipos Windows, ayuda de instalación y mapeos de propietarios más flexibles. SSH y otros proveedores requieren un diseño de autenticación propio.

Si mueves la copia, actualiza su ruta en `$PROFILE`. Respalda `profiles.psd1` antes de eliminarla: Git no guarda tus cuentas.

---

[Made by Karatekah](https://github.com/karatekah)
