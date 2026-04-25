# 🛡️ Xingó Defense Systems

Pacote automatizado para implantação de um Security Operations Center (SOC) focado em ambientes de produção e PMEs.

## Módulos Integrados
* **Wazuh:** SIEM e XDR
* **Shuffle:** SOAR para automação
* **DFIR-IRIS:** Gestão de Incidentes
* **MISP:** Threat Intelligence
* **Cold Storage:** Rotina automatizada de retenção de logs via Rclone (Google Drive).

## Instalação
O instalador cuidará do hardening de SO, emissão de certificados (Let's Encrypt ou Autoassinados) e configuração de restrições de Firewall (DOCKER-USER).

```bash
git clone [https://github.com/SEU_USUARIO/xingo-defense.git](https://github.com/SEU_USUARIO/xingo-defense.git)
cd xingo-defense
chmod +x newsetup.sh
sudo ./newsetup.sh
