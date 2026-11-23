monitorizacion/
├── README.md                  # P1: cómo arrancar agente y panel
├── config.sh                  # P1: URLs de los canales y valores comunes
├── umbrales.json              # P5: umbrales configurables (ampliación A)
│
├── agente.sh                  # P1: script principal del agente
├── panel.sh                   # P4: script principal del panel
│
├── lib/
│   ├── metricas.sh            # P2: cpu_pct, mem, carga, uptime
│   ├── disco_procesos.sh      # P3: disco y top_procesos
│   ├── colores.sh             # P5: cargar_umbrales, color_por_umbral
│   ├── grafica.sh             # P5: mini-gráfica ▁▂▃▄▅▆▇█ (ampliación B)
│   └── alertas.sh             # P5: nivel, comprobar_alerta (ampliación C)
│
├── pruebas/
│   ├── datos_prueba.json      # P4: informes de ejemplo (rojo, normal, antiguo)
│   ├── validar_contrato.sh    # P3: comprueba campos y tipos numéricos
│   └── estres.sh              # P3: yes > /dev/null o stress-ng para la demo
│
├── logs/
│   └── agente.log             # generado: errores de envío del agente
│
├── estado/
│   └── estado_anterior.txt    # generado: último estado de cada host (alertas)
│
└── web/
    └── index.html             # generado por panel.sh --html (si se hace)
