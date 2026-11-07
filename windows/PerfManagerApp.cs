// PerfManager.exe : application Windows (icône près de l'horloge) qui pilote les scripts PerfManager.
// Compilé avec le compilateur C# intégré à Windows (.NET Framework 4.x) : voir windows/build.ps1.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("PerfManager")]
[assembly: AssemblyProduct("PerfManager")]
[assembly: AssemblyDescription("Profils de performance, télécommande PerfDeck et mises à jour")]
[assembly: AssemblyVersion("1.0.0.0")]

namespace PerfManagerApp
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            bool enableAutostart = Array.IndexOf(args, "--enable-autostart") >= 0;
            bool trayOnly = Array.IndexOf(args, "--tray") >= 0;

            bool created;
            using (Mutex mutex = new Mutex(true, "Local\\PerfManagerTrayApp", out created))
            {
                if (!created)
                {
                    // Déjà lancé : on ouvre simplement la fenêtre PerfManager
                    if (!trayOnly) Tray.LaunchGui(root);
                    return;
                }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                if (!File.Exists(Path.Combine(root, "PerfManager.ps1")))
                {
                    MessageBox.Show("PerfManager.ps1 est introuvable à côté de PerfManager.exe.\nRéinstalle PerfManager.", "PerfManager",
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                if (enableAutostart) Tray.SetAutostart(true);
                Application.Run(new Tray(root, !trayOnly));
            }
        }
    }

    class Tray : ApplicationContext
    {
        const string TaskName = "PerfManager";
        const string LegacyTask = "PerfDeck Remote";
        const int Port = 8765;

        readonly string root;
        readonly NotifyIcon icon;
        readonly ContextMenuStrip menu;
        readonly ToolStripMenuItem profilesItem;
        readonly ToolStripMenuItem autostartItem;
        readonly System.Windows.Forms.Timer timer;
        readonly SynchronizationContext ui;
        string activeProfile = null;

        public Tray(string root, bool openGui)
        {
            this.root = root;

            menu = new ContextMenuStrip();
            menu.Font = new Font("Segoe UI", 9.5f);
            ToolStripMenuItem open = new ToolStripMenuItem("Ouvrir PerfManager", null, delegate { LaunchGui(this.root); });
            open.Font = new Font(menu.Font, FontStyle.Bold);
            menu.Items.Add(open);
            profilesItem = new ToolStripMenuItem("Appliquer un profil");
            menu.Items.Add(profilesItem);
            menu.Items.Add(new ToolStripMenuItem("Tout restaurer", null, delegate { RunProfile(null); }));
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("Connecter le téléphone (QR code)", null, delegate { OpenUrl("http://localhost:" + Port + "/pair"); }));
            menu.Items.Add(new ToolStripMenuItem("Rechercher les mises à jour", null, delegate { RunVisible("PerfUpdate.ps1", ""); }));
            autostartItem = new ToolStripMenuItem("Démarrer avec Windows", null, delegate { ToggleAutostart(); });
            menu.Items.Add(autostartItem);
            menu.Items.Add(new ToolStripMenuItem("Ouvrir le dossier", null, delegate { Process.Start("explorer.exe", "\"" + this.root + "\""); }));
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("Quitter", null, delegate { Quit(); }));
            menu.Opening += delegate { BuildProfiles(); autostartItem.Checked = IsAutostart(); };

            ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();

            icon = new NotifyIcon();
            try { icon.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { icon.Icon = SystemIcons.Application; }
            icon.Text = "PerfManager";
            icon.ContextMenuStrip = menu;
            icon.Visible = true;
            icon.DoubleClick += delegate { LaunchGui(this.root); };

            StartServer();

            timer = new System.Windows.Forms.Timer();
            timer.Interval = 4000;
            timer.Tick += delegate { RefreshState(); };
            timer.Start();
            RefreshState();

            if (openGui) LaunchGui(root);
            else Balloon("PerfManager tourne en arrière-plan. Clic droit sur l'icône pour tes profils.");
        }

        // ------------------------------------------------------------ Scripts PowerShell
        static ProcessStartInfo PsInfo(string root, string script, string args, bool hidden)
        {
            string style = hidden ? "-WindowStyle Hidden " : "";
            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass " + style + "-File \"" + Path.Combine(root, script) + "\" " + args);
            psi.WorkingDirectory = root;
            if (hidden) { psi.UseShellExecute = false; psi.CreateNoWindow = true; }
            else { psi.UseShellExecute = true; }
            return psi;
        }

        public static void LaunchGui(string root)
        {
            try { Process.Start(PsInfo(root, "PerfManager.ps1", "", true)); }
            catch (Exception e) { MessageBox.Show("Impossible d'ouvrir PerfManager : " + e.Message, "PerfManager"); }
        }

        void RunVisible(string script, string args)
        {
            try { Process.Start(PsInfo(root, script, args, false)); }
            catch (Exception e) { Balloon("Erreur : " + e.Message); }
        }

        void RunProfile(string name)
        {
            string args = name == null ? "-Restaurer" : "-Profil \"" + name.Replace("\"", "") + "\"";
            string done = name == null ? "PC remis à la normale" : "Profil « " + name + " » appliqué";
            try
            {
                Process p = Process.Start(PsInfo(root, "PerfManager.ps1", args, true));
                p.EnableRaisingEvents = true;
                p.Exited += delegate { ui.Post(delegate { Balloon(done); RefreshState(); }, null); };
                Balloon(name == null ? "Restauration en cours…" : "Application de « " + name + " »…");
            }
            catch (Exception e) { Balloon("Erreur : " + e.Message); }
        }

        // ------------------------------------------------------------ Serveur PerfDeck (téléphone)
        static bool PortOpen()
        {
            try
            {
                using (TcpClient c = new TcpClient())
                {
                    IAsyncResult r = c.BeginConnect("127.0.0.1", Port, null, null);
                    bool ok = r.AsyncWaitHandle.WaitOne(400) && c.Connected;
                    return ok;
                }
            }
            catch { return false; }
        }

        void StartServer()
        {
            if (PortOpen()) return;   // déjà lancé (ancienne tâche planifiée, autre session…)
            if (!File.Exists(Path.Combine(root, "PerfRemote.ps1"))) return;
            try { Process.Start(PsInfo(root, "PerfRemote.ps1", "-NoPair", true)); } catch { }
        }

        void StopServer()
        {
            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:" + Port + "/api/quit");
                req.Timeout = 2000;
                using (req.GetResponse()) { }
            }
            catch { }
        }

        // ------------------------------------------------------------ Profils et état
        List<KeyValuePair<string, bool>> ReadProfiles()
        {
            List<KeyValuePair<string, bool>> list = new List<KeyValuePair<string, bool>>();
            try
            {
                string json = File.ReadAllText(Path.Combine(root, "profiles.json"));
                Dictionary<string, object> cfg = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json);
                ArrayList profiles = cfg["profiles"] as ArrayList;
                if (profiles == null) return list;
                foreach (object o in profiles)
                {
                    Dictionary<string, object> p = o as Dictionary<string, object>;
                    if (p == null || !p.ContainsKey("name")) continue;
                    bool restore = p.ContainsKey("restore") && p["restore"] is bool && (bool)p["restore"];
                    list.Add(new KeyValuePair<string, bool>(Convert.ToString(p["name"]), restore));
                }
            }
            catch { }
            return list;
        }

        void BuildProfiles()
        {
            profilesItem.DropDownItems.Clear();
            List<KeyValuePair<string, bool>> profiles = ReadProfiles();
            if (profiles.Count == 0)
            {
                ToolStripMenuItem none = new ToolStripMenuItem("profiles.json illisible");
                none.Enabled = false;
                profilesItem.DropDownItems.Add(none);
                return;
            }
            foreach (KeyValuePair<string, bool> p in profiles)
            {
                string name = p.Key;
                ToolStripMenuItem item = new ToolStripMenuItem(name, null, delegate { RunProfile(name); });
                item.Checked = name == activeProfile;
                profilesItem.DropDownItems.Add(item);
            }
        }

        void RefreshState()
        {
            string profile = null;
            try
            {
                string state = Path.Combine(root, "state.json");
                if (File.Exists(state))
                {
                    Dictionary<string, object> s = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(state));
                    if (s.ContainsKey("profile") && s["profile"] != null) profile = Convert.ToString(s["profile"]);
                }
            }
            catch { }
            activeProfile = profile;
            string text = profile == null ? "PerfManager : état normal" : "PerfManager : " + profile;
            icon.Text = text.Length > 63 ? text.Substring(0, 63) : text;
        }

        // ------------------------------------------------------------ Démarrage avec Windows
        static int Schtasks(string args)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo("schtasks.exe", args);
                psi.UseShellExecute = false; psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true; psi.RedirectStandardError = true;
                using (Process p = Process.Start(psi)) { p.StandardOutput.ReadToEnd(); p.WaitForExit(10000); return p.ExitCode; }
            }
            catch { return -1; }
        }

        static bool IsAutostart() { return Schtasks("/Query /TN \"" + TaskName + "\"") == 0; }

        public static bool SetAutostart(bool on)
        {
            if (!on) return Schtasks("/Delete /TN \"" + TaskName + "\" /F") == 0;
            Schtasks("/Delete /TN \"" + LegacyTask + "\" /F");   // l'appli lance déjà le serveur
            string exe = Application.ExecutablePath;
            return Schtasks("/Create /TN \"" + TaskName + "\" /TR \"\\\"" + exe + "\\\" --tray\" /SC ONLOGON /RL HIGHEST /F") == 0;
        }

        void ToggleAutostart()
        {
            bool on = !IsAutostart();
            if (SetAutostart(on)) Balloon(on ? "PerfManager démarrera avec Windows" : "Démarrage automatique désactivé");
            else Balloon("Impossible de modifier le démarrage automatique");
        }

        // ------------------------------------------------------------ Divers
        void Balloon(string text)
        {
            icon.BalloonTipTitle = "PerfManager";
            icon.BalloonTipText = text;
            icon.ShowBalloonTip(3000);
        }

        void OpenUrl(string url)
        {
            StartServer();
            try { Process.Start(url); } catch (Exception e) { Balloon("Erreur : " + e.Message); }
        }

        void Quit()
        {
            timer.Stop();
            StopServer();
            icon.Visible = false;
            icon.Dispose();
            ExitThread();
        }
    }
}
