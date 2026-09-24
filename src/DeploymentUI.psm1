Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-DeploymentUI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Config,
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [string] $InitialMode
    )

    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Windows Deployment" Height="720" Width="960" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Background="#F5F7FA">
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="120"/><RowDefinition Height="*"/><RowDefinition Height="90"/></Grid.RowDefinitions>
    <Border Grid.Row="0" Background="White" BorderBrush="#E5E7EB" BorderThickness="0,0,0,1">
      <Grid Margin="36,20"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center"><TextBlock Name="CustomerName" FontSize="28" FontWeight="SemiBold"/><TextBlock Name="Heading" FontSize="16" Foreground="#6B7280" Margin="0,6,0,0"/></StackPanel>
        <Image Name="Logo" Grid.Column="1" MaxHeight="70" MaxWidth="220" Stretch="Uniform" Visibility="Collapsed"/>
      </Grid>
    </Border>
    <Grid Grid.Row="1" Margin="36,28"><Grid.ColumnDefinitions><ColumnDefinition Width="1.1*"/><ColumnDefinition Width="24"/><ColumnDefinition Width="0.9*"/></Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0">
        <TextBlock Text="DEPLOYMENT" FontSize="12" FontWeight="Bold" Foreground="#6B7280" Margin="0,0,0,14"/>
        <TextBlock Text="Mode"/><ComboBox Name="Mode" Height="36" Margin="0,6,0,14"/>
        <TextBlock Text="Deployment profile"/><ComboBox Name="Profile" Height="36" Margin="0,6,0,14" DisplayMemberPath="displayName"/>
        <TextBlock Text="Windows version"/><ComboBox Name="WindowsVersion" Height="36" Margin="0,6,0,14"/>
        <TextBlock Text="Edition"/><ComboBox Name="Edition" Height="36" Margin="0,6,0,14"/>
        <TextBlock Text="Language"/><ComboBox Name="Language" Height="36" Margin="0,6,0,14"/>
        <TextBlock Text="Drivers"/><ComboBox Name="Drivers" Height="36" Margin="0,6,0,14"/>
        <TextBlock Text="Autopilot Group Tag"/><ComboBox Name="GroupTag" Height="36" Margin="0,6,0,0" DisplayMemberPath="displayName"/>
      </StackPanel>
      <StackPanel Grid.Column="2">
        <TextBlock Text="DEVICE" FontSize="12" FontWeight="Bold" Foreground="#6B7280" Margin="0,0,0,14"/>
        <Border Background="White" CornerRadius="8" Padding="20" BorderBrush="#E5E7EB" BorderThickness="1">
          <StackPanel><TextBlock Name="DeviceModel" FontSize="18" FontWeight="SemiBold"/><TextBlock Name="Serial" Foreground="#6B7280" Margin="0,5,0,0"/><TextBlock Name="DeploymentId" Foreground="#9CA3AF" FontSize="11" Margin="0,12,0,0" TextWrapping="Wrap"/></StackPanel>
        </Border>
        <TextBlock Text="PREFLIGHT" FontSize="12" FontWeight="Bold" Foreground="#6B7280" Margin="0,26,0,14"/>
        <Border Background="White" CornerRadius="8" Padding="20" BorderBrush="#E5E7EB" BorderThickness="1"><StackPanel><TextBlock Name="Internet" Margin="0,0,0,10"/><TextBlock Name="TPM" Margin="0,0,0,10"/><TextBlock Name="SecureBoot"/></StackPanel></Border>
        <TextBlock Name="SupportText" Foreground="#6B7280" TextWrapping="Wrap" Margin="0,24,0,0"/>
      </StackPanel>
    </Grid>
    <Border Grid.Row="2" Background="White" BorderBrush="#E5E7EB" BorderThickness="0,1,0,0"><Grid Margin="36,18"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="12"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Name="Summary" VerticalAlignment="Center" Foreground="#4B5563"/><Button Name="Cancel" Grid.Column="1" Content="Cancel" Width="110" Height="42"/><Button Name="Start" Grid.Column="3" Content="START DEPLOYMENT" Width="180" Height="42" FontWeight="SemiBold"/></Grid></Border>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $get = { param($n) $window.FindName($n) }

    $customerName=&$get 'CustomerName'; $heading=&$get 'Heading'; $logo=&$get 'Logo'; $mode=&$get 'Mode'; $profile=&$get 'Profile'; $win=&$get 'WindowsVersion'; $edition=&$get 'Edition'; $language=&$get 'Language'; $drivers=&$get 'Drivers'; $tag=&$get 'GroupTag'
    $customerName.Text=$Config.customer.displayName; $heading.Text=$Config.customer.branding.heading
    if ($Config.customer.branding.supportText) { (&$get 'SupportText').Text=$Config.customer.branding.supportText }
    $window.Title=$Config.customer.branding.windowTitle
    if ($Config.customer.branding.logoUri) { try { $logo.Source=[Windows.Media.Imaging.BitmapImage]::new([uri]$Config.customer.branding.logoUri); $logo.Visibility='Visible' } catch {} }

    @($Config.deployment.allowedModes) | ForEach-Object { [void]$mode.Items.Add($_) }
    @($Config.deployment.profiles) | ForEach-Object { [void]$profile.Items.Add($_) }
    @($Config.options.windowsVersions.allowed) | ForEach-Object { [void]$win.Items.Add($_) }
    @($Config.options.editions.allowed) | ForEach-Object { [void]$edition.Items.Add($_) }
    @($Config.options.languages.allowed) | ForEach-Object { [void]$language.Items.Add($_) }
    @($Config.options.drivers.allowed) | ForEach-Object { [void]$drivers.Items.Add($_) }
    @($Config.autopilot.groupTags) | ForEach-Object { [void]$tag.Items.Add($_) }

    $mode.SelectedItem=if($InitialMode){$InitialMode}else{$Config.deployment.defaultMode}
    $profile.SelectedItem=@($Config.deployment.profiles)|Where-Object default -eq $true|Select-Object -First 1
    $win.SelectedItem=$Config.options.windowsVersions.default; $edition.SelectedItem=$Config.options.editions.default; $language.SelectedItem=$Config.options.languages.default; $drivers.SelectedItem=$Config.options.drivers.default
    $tag.SelectedItem=@($Config.autopilot.groupTags)|Where-Object default -eq $true|Select-Object -First 1

    (&$get 'DeviceModel').Text="$($Context.Manufacturer) $($Context.Model)"; (&$get 'Serial').Text="Serial: $($Context.SerialNumber)"; (&$get 'DeploymentId').Text="Deployment ID: $($Context.DeploymentId)"
    $preflight=Test-DeploymentPreflight -Config $Config
    (&$get 'Internet').Text="$(if($preflight.Internet){'✓'}else{'✗'}) Internet"; (&$get 'TPM').Text="$(if($preflight.TpmReady){'✓'}else{'⚠'}) TPM ready"; (&$get 'SecureBoot').Text="$(if($preflight.SecureBoot){'✓'}else{'⚠'}) Secure Boot"

    $applyProfile = {
        if ($profile.SelectedItem) { $p=$profile.SelectedItem; $win.SelectedItem=$p.windowsVersion; $edition.SelectedItem=$p.edition; $language.SelectedItem=$p.language; $drivers.SelectedItem=$p.drivers; $tag.SelectedItem=@($Config.autopilot.groupTags)|Where-Object value -eq $p.groupTag|Select-Object -First 1 }
    }
    $profile.Add_SelectionChanged($applyProfile)

    $setMode = {
        $isZti=($mode.SelectedItem -eq 'ZTI'); $profile.IsEnabled=$true
        foreach($c in @($win,$edition,$language,$drivers,$tag)){ $c.IsEnabled = -not $isZti }
        (&$get 'Summary').Text=if($isZti){'ZTI: customer profile values are locked.'}else{'Review the customer-approved deployment options before starting.'}
    }
    $mode.Add_SelectionChanged($setMode); &$setMode

    $script:uiResult=$null
    (&$get 'Cancel').Add_Click({$window.DialogResult=$false;$window.Close()})
    (&$get 'Start').Add_Click({
        if(-not $profile.SelectedItem -or -not $tag.SelectedItem){[System.Windows.MessageBox]::Show('Select a deployment profile and Group Tag.','Deployment')|Out-Null;return}
        $script:uiResult=[pscustomobject]@{Mode=[string]$mode.SelectedItem;ProfileId=$profile.SelectedItem.id;ProfileName=$profile.SelectedItem.displayName;WindowsVersion=[string]$win.SelectedItem;Edition=[string]$edition.SelectedItem;Language=[string]$language.SelectedItem;Drivers=[string]$drivers.SelectedItem;GroupTag=$tag.SelectedItem.value}
        $window.DialogResult=$true;$window.Close()
    })
    [void]$window.ShowDialog(); return $script:uiResult
}

Export-ModuleMember -Function Show-DeploymentUI
