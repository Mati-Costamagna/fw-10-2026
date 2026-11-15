"""Grafica los datos del ADC que imprime test_adc / test_drivers por UART0.

  python3 plot_adc.py [log]     (default: fw/build/sim.log, la salida del ultimo make sim)

El log de un test corrido con make test_adc es fw/build/test_adc.sim.log.
"""
import os
import re
import sys
import matplotlib.pyplot as plt

# Leer el archivo (por defecto, busca el log del ultimo make sim en rutas comunes)
script_dir = os.path.dirname(os.path.abspath(__file__))
if len(sys.argv) > 1:
    log_path = sys.argv[1]
else:
    candidates = [
        os.path.join(script_dir, '..', 'build', 'sim.log'),
        os.path.join(script_dir, '..', '..', 'platform', 'fw', 'build', 'sim.log'),
    ]
    log_path = next((p for p in candidates if os.path.isfile(p)), candidates[0])

if not os.path.isfile(log_path):
    print(f"No existe el log: {log_path}")
    print("Sugerencia: corre make sim y/o pasa la ruta manualmente:")
    print("  python3 fw/tools/plot_adc.py platform/fw/build/sim.log")
    sys.exit(1)

try:
    with open(log_path, 'r', encoding='utf-8') as f:
        content = f.read()
except UnicodeDecodeError:
    with open(log_path, 'r', encoding='latin-1') as f:
        content = f.read()

# Buscar el punto de inicio
marker = "ADC data read"
start_idx = content.find(marker)

if start_idx == -1:
    print("No se encontró el marcador")
    exit(1)

# Extraer todo después del marcador
data_section = content[start_idx:]

# Buscar todos los números después del marcador
# Patrón: "UART: " seguido de números
adc_values = []
for line in data_section.split('\n'):
    # Buscar líneas que comiencen con "UART: " seguidas de dígitos
    match = re.search(r'UART: (\d+)', line)
    if match:
        # Saltear la línea del marcador mismo
        if "ADC data read" not in line:
            adc_values.append(int(match.group(1)))

print(f"Se extrajeron {len(adc_values)} valores")
print(f"Primeros 10: {adc_values[:10]}")

vref = 3.3
fullscale = (2**32) - 1
volts = [x * vref / fullscale for x in adc_values]

# Plotear
plt.figure(figsize=(12, 6))
plt.plot(volts, linewidth=1.5)
plt.xlabel('Muestra')
plt.ylabel('Voltaje [V]')
plt.title('Datos del ADC')
plt.grid(True, alpha=0.3)
plt.tight_layout()
png_path = os.path.join(os.path.dirname(os.path.abspath(log_path)), 'adc_plot.png')
plt.savefig(png_path, dpi=150)
plt.show()

print(f"Gráfico guardado como {png_path}")
