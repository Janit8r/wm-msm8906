#!/usr/bin/env python3
import re

SKIP = {'tweaks'}

DEFAULT_TMPL = [
    'CONFIG_DEFAULT_qcom-msm8916-modem-openstick-{dev}-firmware',
    'CONFIG_DEFAULT_qcom-msm8916-openstick-{dev}-wcnss-firmware',
    'CONFIG_DEFAULT_qcom-msm8916-wcnss-openstick-{dev}-nv',
]

def extract_dev(s):
    m = re.search(r'openstick-([a-zA-Z0-9]+)', s)
    return m.group(1) if m else None

def main(input_file='.config'):
    with open(input_file) as f:
        src = f.readlines()

    devices = sorted(set(
        d for d in (extract_dev(ln) for ln in src if 'openstick-' in ln)
        if d and d not in SKIP
    ))
    print('扫描到设备:', devices)

    for target in devices:
        out = []
        for ln in src:
            s = ln.strip()

            m_dev = re.match(r'(# )?CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-([a-zA-Z0-9]+)', s)
            if m_dev:
                dev = m_dev.group(2)
                out.append('CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-%s=y\n' % dev
                           if dev == target else
                           '# CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-%s is not set\n' % dev)
                continue

            if s.startswith('CONFIG_TARGET_PROFILE='):
                out.append('CONFIG_TARGET_PROFILE="DEVICE_openstick-%s"\n' % target)
                continue

            # DEFAULT 固件行：凡是属于某机型的 DEFAULT 模板行，跳过，后面统一按 target 重写
            m_def = re.match(r'#?\s*(CONFIG_DEFAULT_qcom-msm8916-[^\s=]+)', s)
            if m_def and 'openstick-' in s and any(t.split('{dev}')[0] in s for t in DEFAULT_TMPL):
                continue

            # PACKAGE 固件行：名字不动，目标开、其他关
            m_fw = re.match(r'#?\s*(CONFIG_PACKAGE_qcom-msm8916-[^\s=]+)', s)
            if m_fw and 'openstick-' in s:
                name = m_fw.group(1).split('=')[0].split(' is not set')[0].strip()
                dev = extract_dev(name)
                out.append('%s=y\n' % name if dev == target else '# %s is not set\n' % name)
                continue

            out.append(ln)

        # 在同位置补上 target 自己的 DEFAULT 三行（插在 rmtfs 前，位置贴近原 DEFAULT 段）
        at = next((i for i, l in enumerate(out) if l.strip().startswith('CONFIG_DEFAULT_rmtfs')), len(out))
        out[at:at] = ['%s=y\n' % t.format(dev=target) for t in DEFAULT_TMPL]

        with open('%s.config' % target, 'w') as f:
            f.writelines(out)
        print('  生成:', target + '.config')

    print('全部完成，共 %d 个' % len(devices))

if __name__ == '__main__':
    main()