import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class AppLocalizations {
  const AppLocalizations(this.lang);
  final String lang; // 'en' | 'fr' | 'es'

  String _p({required String en, required String fr, required String es}) {
    switch (lang) {
      case 'fr': return fr;
      case 'es': return es;
      default:   return en;
    }
  }

  // ── General ──────────────────────────────────────────────
  String get appName       => _p(en: 'AudioRouter',   fr: 'AudioRouter',   es: 'AudioRouter');
  String get settings      => _p(en: 'Settings',      fr: 'Paramètres',    es: 'Ajustes');
  String get done          => _p(en: 'Done',           fr: 'Terminé',       es: 'Hecho');
  String get cancel        => _p(en: 'Cancel',         fr: 'Annuler',       es: 'Cancelar');
  String get add           => _p(en: 'Add',            fr: 'Ajouter',       es: 'Añadir');
  String get reset         => _p(en: 'Reset',          fr: 'Réinitialiser', es: 'Restablecer');
  String get resetTooltip  => _p(en: 'Reset all to default device', fr: 'Réinitialiser vers le périphérique par défaut', es: 'Restablecer al dispositivo predeterminado');
  String get search        => _p(en: 'Search apps…',  fr: 'Rechercher…',   es: 'Buscar apps…');
  String get noMatch       => _p(en: 'No matching app', fr: 'Aucune app correspondante', es: 'Sin coincidencias');
  String get save          => _p(en: 'Save',           fr: 'Enregistrer',   es: 'Guardar');
  String get newProfile    => _p(en: 'New profile',    fr: 'Nouveau profil', es: 'Nuevo perfil');
  String get editProfile   => _p(en: 'Edit profile',   fr: 'Modifier le profil', es: 'Editar perfil');
  String get profileName   => _p(en: 'Profile name',   fr: 'Nom du profil', es: 'Nombre del perfil');
  String get deleteProfile => _p(en: '🗑 Delete',      fr: '🗑 Supprimer',  es: '🗑 Eliminar');
  String get audioOutputs  => _p(en: 'Audio outputs',  fr: 'Sorties audio', es: 'Salidas de audio');
  String get defaultLabel  => _p(en: 'default',        fr: 'défaut',        es: 'defecto');
  String get connected     => _p(en: 'connected',      fr: 'connecté',      es: 'conectado');
  String get disconnected  => _p(en: 'disconnected',   fr: 'déconnecté',    es: 'desconectado');

  // ── Duck rules ────────────────────────────────────────────
  String get autoDuck      => _p(en: 'Auto-Duck',     fr: 'Auto-Duck',     es: 'Auto-Duck');
  String get noRules       => _p(en: 'No rules yet',  fr: 'Aucune règle',  es: 'Sin reglas');
  String get noRulesHint   => _p(en: 'e.g. Discord active → lower Spotify to 30%', fr: 'ex. Discord actif → baisser Spotify à 30%', es: 'ej. Discord activo → bajar Spotify al 30%');
  String get addRule       => _p(en: '+ Add rule',    fr: '+ Ajouter règle', es: '+ Añadir regla');
  String get newDuckRule   => _p(en: 'New Duck Rule', fr: 'Nouvelle règle Auto-Duck', es: 'Nueva regla Auto-Duck');
  String get whenAppActive => _p(en: 'When this app is active:', fr: 'Quand cette app est active :', es: 'Cuando esta app está activa:');
  String get lowerAppTo    => _p(en: 'Lower this app to:',       fr: 'Baisser cette app à :',         es: 'Bajar esta app a:');

  // ── Session ───────────────────────────────────────────────
  String get noAudio       => _p(en: 'No audio',      fr: 'Pas de son',    es: 'Sin audio');
  String get mute          => _p(en: 'Mute',          fr: 'Muet',          es: 'Silenciar');
  String get unmute        => _p(en: 'Unmute',        fr: 'Activer',       es: 'Activar');

  // ── Settings ──────────────────────────────────────────────
  String get darkMode      => _p(en: 'Dark mode',     fr: 'Mode sombre',   es: 'Modo oscuro');
  String get darkModeDesc  => _p(en: 'Toggle between dark and light theme', fr: 'Basculer entre thème sombre et clair', es: 'Alternar entre tema oscuro y claro');
  String get launchStartup => _p(en: 'Launch at startup', fr: 'Lancer au démarrage', es: 'Iniciar al arranque');
  String get launchStartupDescWin => _p(en: 'Start AudioRouter when Windows starts', fr: 'Démarrer AudioRouter au lancement de Windows', es: 'Iniciar AudioRouter al arrancar Windows');
  String get launchStartupDescMac => _p(en: 'Start AudioRouter when macOS starts', fr: 'Démarrer AudioRouter au lancement de macOS', es: 'Iniciar AudioRouter al arrancar macOS');
  String get interfaceStyle => _p(en: 'Interface style', fr: 'Style d\'interface', es: 'Estilo de interfaz');
  String get interfaceStyleDesc => _p(en: 'Choose between Windows 11 and macOS look', fr: 'Choisir entre l\'apparence Windows 11 et macOS', es: 'Elegir entre apariencia Windows 11 y macOS');
  String get profiles      => _p(en: 'Profiles',      fr: 'Profils',       es: 'Perfiles');
  String get exportProfiles => _p(en: 'Export',       fr: 'Exporter',      es: 'Exportar');
  String get importProfiles => _p(en: 'Import',       fr: 'Importer',      es: 'Importar');
  String get exportProfilesMac => _p(en: 'Export profiles', fr: 'Exporter les profils', es: 'Exportar perfiles');
  String get importProfilesMac => _p(en: 'Import profiles', fr: 'Importer les profils', es: 'Importar perfiles');
  String get copyToClipboard => _p(en: 'Copy to clipboard', fr: 'Copier dans le presse-papiers', es: 'Copiar al portapapeles');
  String get pasteFromClipboard => _p(en: 'Paste from clipboard', fr: 'Coller depuis le presse-papiers', es: 'Pegar del portapapeles');
  String get language      => _p(en: 'Language',      fr: 'Langue',        es: 'Idioma');
  String get general       => _p(en: 'General',       fr: 'Général',       es: 'General');

  // ── Notifications ─────────────────────────────────────────
  String exportedN(int n) => _p(
    en: 'Profiles exported! ($n profiles)',
    fr: 'Profils exportés ! ($n profils)',
    es: '¡Perfiles exportados! ($n perfiles)',
  );
  String get exportFailed  => _p(en: 'Export failed', fr: 'Échec de l\'export', es: 'Error al exportar');
  String get clipboardEmpty => _p(en: 'Clipboard is empty', fr: 'Presse-papiers vide', es: 'Portapapeles vacío');
  String get importFailed  => _p(en: 'Import failed', fr: 'Échec de l\'import', es: 'Error al importar');
  String importedN(int n)  => _p(
    en: 'Imported $n profiles!',
    fr: '$n profils importés !',
    es: '¡$n perfiles importados!',
  );

  // ── macOS routing banner ──────────────────────────────────
  String routingLimitedTitle(String version) => _p(
    en: 'Limited routing — macOS $version',
    fr: 'Routage limité — macOS $version',
    es: 'Enrutamiento limitado — macOS $version',
  );
  String get routingLimitedBody => _p(
    en: 'Per-app routing requires macOS 14.2 (Sonoma).\n'
        'Devices and volumes are visible, '
        'but audio will stay on the system device.',
    fr: 'Le routage par app nécessite macOS 14.2 (Sonoma).\n'
        'Les périphériques et volumes sont visibles, '
        'mais l\'audio restera sur le device système.',
    es: 'El enrutamiento por app requiere macOS 14.2 (Sonoma).\n'
        'Los dispositivos y volúmenes son visibles, '
        'pero el audio permanecerá en el dispositivo del sistema.',
  );

  // ── Donation ──────────────────────────────────────────────
  String get supportProject => _p(en: 'Support the project', fr: 'Soutenir le projet', es: 'Apoyar el proyecto');
  String get donateTitle    => _p(en: 'Support AudioRouter ❤️', fr: 'Soutenir AudioRouter ❤️', es: 'Apoyar AudioRouter ❤️');
  String get donateBody     => _p(
    en: 'AudioRouter is free and open source.\nIf you find it useful, consider buying me a coffee or making a small donation — it helps a lot!',
    fr: 'AudioRouter est gratuit et open source.\nSi vous le trouvez utile, offrez-moi un café ou faites un petit don — ça aide beaucoup !',
    es: 'AudioRouter es gratuito y de código abierto.\nSi te resulta útil, invítame a un café o haz una pequeña donación — ¡ayuda mucho!',
  );
  String get donateCoffee   => _p(en: 'Buy Me a Coffee', fr: 'Buy Me a Coffee', es: 'Buy Me a Coffee');
  String get maybeLater     => _p(en: 'Maybe later', fr: 'Peut-être plus tard', es: 'Quizás más tarde');
  String get showInDock     => _p(en: 'Show in Dock', fr: 'Afficher dans le Dock', es: 'Mostrar en el Dock');
  String get showInTaskbar  => _p(en: 'Show in taskbar', fr: 'Afficher dans la barre des tâches', es: 'Mostrar en la barra de tareas');
  String get showInTaskbarDesc => _p(
    en: 'Keep the app visible in the Dock / taskbar.',
    fr: 'Maintenir l\'app visible dans le Dock / la barre des tâches.',
    es: 'Mantener la app visible en el Dock / barra de tareas.',
  );
  String get thankYou       => _p(en: 'Thank you! ❤️', fr: 'Merci ! ❤️', es: '¡Gracias! ❤️');

  // ── Auto-Update ───────────────────────────────────────────
  String get updateAvailable => _p(en: 'Update Available', fr: 'Mise à jour disponible', es: 'Actualización Disponible');
  String get updateBody      => _p(
    en: 'A new version of AudioRouter is available on GitHub.',
    fr: 'Une nouvelle version d\'AudioRouter est disponible sur GitHub.',
    es: 'Hay una nueva versión de AudioRouter disponible en GitHub.',
  );
  String get downloadUpdate  => _p(en: 'Download', fr: 'Télécharger', es: 'Descargar');
  String get installUpdate   => _p(en: 'Install Update', fr: 'Installer la mise à jour', es: 'Instalar actualización');
  String get downloading     => _p(en: 'Downloading...', fr: 'Téléchargement...', es: 'Descargando...');
  String get skipUpdate      => _p(en: 'Skip this version', fr: 'Ignorer cette version', es: 'Omitir esta versión');
  String get checkUpdates    => _p(en: 'Check for updates at startup', fr: 'Chercher les MAJ au démarrage', es: 'Buscar actualizaciones al inicio');
}


extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n {
    final ts = read<ThemeService>();
    return AppLocalizations(ts.locale);
  }
}
