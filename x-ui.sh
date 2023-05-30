#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

#Add some basic function here
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}
# check root
[[ $EUID -ne 0 ]] && LOGE "错误:  必须使用root用户运行此脚本!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    LOGE "未检测到系统版本，请联系脚本作者！\n" && exit 1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        LOGE "请使用 CentOS 7 或更高版本的系统！\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        LOGE "请使用 Ubuntu 16 或更高版本的系统！\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        LOGE "请使用 Debian 8 或更高版本的系统！\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Whether to restart the panel, restarting the panel will also restart xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Press enter to return to the main menu: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "本功能会强制重装当前最新版，数据不会丢失，是否继续?" "n"
    if [[ $? != 0 ]]; then
        LOGE "已取消"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "更新完成，已自动重启面板 "
        exit 0
    fi
}

uninstall() {
    confirm "确定要卸载面板吗,xray 也会卸载?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop x-ui
    systemctl disable x-ui
    rm /etc/systemd/system/x-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/x-ui -f${plain} 进行删除"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

reset_user() {
    confirm "Make sure you want to reset your username and password to admin is it" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -username admin -password admin
    echo -e "Username and password have been reset to ${green}admin${plain}，Please restart the panel now"
    confirm_restart
}

reset_config() {
    confirm "Are you sure you want to reset all panel settings, account data will not be lost, user name and password will not change" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "All panel settings have been reset to default, please restart the panel now and use the default ${green}54321${plain} Port Access Panel"
    confirm_restart
}

check_config() {
    info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "get current settings error,please check logs"
        show_menu
    fi
    LOGI "${info}"
}

set_port() {
    echo && echo -n -e "输入端口号[1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        LOGD "已取消"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        echo -e "The port is set, now please restart the panel and use the newly set port ${green}${port}${plain} to access the panel"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "The panel is already running and there is no need to start it again. If you need to restart it, please select Restart"
    else
        systemctl start x-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "x-ui Start successfully"
        else
            LOGE "The panel failed to start, it may be because the startup time exceeds two seconds, please check the log information later"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "面板已停止，无需再次停止"
    else
        systemctl stop x-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui 与 xray 停止成功"
        else
            LOGE "面板停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart x-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "x-ui 与 xray 重启成功"
    else
        LOGE "面板重启失败，可能是因为启动时间超过了两秒，请稍后查看日志信息"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status x-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui 设置开机自启成功"
    else
        LOGE "x-ui 设置开机自启失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui 取消开机自启成功"
    else
        LOGE "x-ui 取消开机自启失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u x-ui.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

migrate_v2_ui() {
    /usr/local/x-ui/x-ui v2-ui

    before_show_menu
}

install_bbr() {
    # temporary workaround for installing bbr
    bash <(curl -L -s https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
    echo ""
    before_show_menu
}

update_shell() {
    wget -O /usr/bin/x-ui -N --no-check-certificate https://github.com/vaxilu/x-ui/raw/master/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "下载脚本失败，请检查本机能否连接 Github"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "升级脚本成功，请重新运行脚本" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled x-ui)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "面板已安装，请不要重复安装"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "请先安装面板"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "面板状态: ${green}已运行${plain}"
        show_enable_status
        ;;
    1)
        echo -e "面板状态: ${yellow}未运行${plain}"
        show_enable_status
        ;;
    2)
        echo -e "面板状态: ${red}未安装${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "xray 状态: ${green}运行${plain}"
    else
        echo -e "xray 状态: ${red}未运行${plain}"
    fi
}

ssl_cert_issue() {
    echo -E ""
    LOGD "******Instructions******"
    LOGI "This script will use the Acme script to apply for a certificate. When using it, you must ensure:"
    LOGI "1. Know the Cloudflare registered email address"
    LOGI "2. Know Cloudflare Global API Key"
    LOGI "3. The domain name has been resolved to the current server by Cloudflare"
    LOGI "4. The default installation path for this script to apply for a certificate is the /root/cert directory"
    confirm "I have confirmed the above [y/n]" "y"
    if [ $? -eq 0 ]; then
        cd ~
        LOGI "安装Acme脚本"
        curl https://get.acme.sh | sh
        if [ $? -ne 0 ]; then
            LOGE "Failed to install acme script"
            exit 1
        fi
        CF_Domain=""
        CF_GlobalKey=""
        CF_AccountEmail=""
        certPath=/root/cert
        if [ ! -d "$certPath" ]; then
            mkdir $certPath
        else
            rm -rf $certPath
            mkdir $certPath
        fi
        LOGD "请设置域名:"
        read -p "Input your domain here:" CF_Domain
        LOGD "你的域名设置为:${CF_Domain}"
        LOGD "请设置API密钥:"
        read -p "Input your key here:" CF_GlobalKey
        LOGD "你的API密钥为:${CF_GlobalKey}"
        LOGD "请设置注册邮箱:"
        read -p "Input your email here:" CF_AccountEmail
        LOGD "你的注册邮箱为:${CF_AccountEmail}"
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "Modify the default CA to Lets'Encrypt failed, the script exits"
            exit 1
        fi
        export CF_Key="${CF_GlobalKey}"
        export CF_Email=${CF_AccountEmail}
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log
        if [ $? -ne 0 ]; then
            LOGE "证书签发失败,脚本退出"
            exit 1
        else
            LOGI "证书签发成功,安装中..."
        fi
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} --ca-file /root/cert/ca.cer \
        --cert-file /root/cert/${CF_Domain}.cer --key-file /root/cert/${CF_Domain}.key \
        --fullchain-file /root/cert/fullchain.cer
        if [ $? -ne 0 ]; then
            LOGE "证书安装失败,脚本退出"
            exit 1
        else
            LOGI "证书安装成功,开启自动更新..."
        fi
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "自动更新设置失败,脚本退出"
            ls -lah cert
            chmod 755 $certPath
            exit 1
        else
            LOGI "证书已安装且已开启自动更新,具体信息如下"
            ls -lah cert
            chmod 755 $certPath
        fi
    else
        show_menu
    fi
}

show_usage() {
    echo "How to use x-ui management script:"
    echo "------------------------------------------"
    echo "x-ui - show admin menu (more features)"
    echo "x-ui start - start x-ui panel"
    echo "x-ui stop - stop x-ui panel"
    echo "x-ui restart - restart the x-ui panel"
    echo "x-ui status - view x-ui status"
    echo "x-ui enable - set x-ui to boot automatically"
    echo "x-ui disable - cancel x-ui boot automatically"
    echo "x-ui log - view x-ui log"
    echo "x-ui v2-ui - migrate the v2-ui account data of this machine to x-ui"
    echo "x-ui update - update x-ui panel"
    echo "x-ui install - install x-ui panel"
    echo "x-ui uninstall - uninstall x-ui panel"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}x-ui panel management script ${plain}
  ${green}0.${plain} exit script
———————————————
  ${green}1.${plain} install x-ui
  ${green}2.${plain} update x-ui
  ${green}3.${plain} uninstall x-ui
———————————————
  ${green}4.${plain} Reset username and password
  ${green}5.${plain} Reset panel settings
  ${green}6.${plain} set the panel port
  ${green}7.${plain} View the current panel settings
———————————————
  ${green}8.${plain} start x-ui
  ${green}9.${plain} stop x-ui
  ${green}10.${plain} restart x-ui
  ${green}11.${plain} View x-ui status
  ${green}12.${plain} View x-ui logs
———————————————
  ${green}13.${plain} set x-ui to boot automatically
  ${green}14.${plain} cancel x-ui autostart
———————————————
  ${green}15.${plain} One-click installation of bbr (latest kernel)
  ${green}16.${plain} One-click application for SSL certificate (acme application)
 "
    show_status
    echo && read -p "please enter selection [0-16]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && uninstall
        ;;
    4)
        check_install && reset_user
        ;;
    5)
        check_install && reset_config
        ;;
    6)
        check_install && set_port
        ;;
    7)
        check_install && check_config
        ;;
    8)
        check_install && start
        ;;
    9)
        check_install && stop
        ;;
    10)
        check_install && restart
        ;;
    11)
        check_install && status
        ;;
    12)
        check_install && show_log
        ;;
    13)
        check_install && enable
        ;;
    14)
        check_install && disable
        ;;
    15)
        install_bbr
        ;;
    16)
        ssl_cert_issue
        ;;
    *)
        LOGE "Please enter the correct number [0-16]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "log")
        check_install 0 && show_log 0
        ;;
    "v2-ui")
        check_install 0 && migrate_v2_ui 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
