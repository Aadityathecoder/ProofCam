// Line icons drawn for ProofCam's web version, standing in for the app's SF Symbols.
const svg = (body, size = 22) =>
  `<svg class="icon" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;

export const icons = {
  camera: (s) => svg('<path d="M3.5 8.5A1.5 1.5 0 0 1 5 7h2.6l1.5-2h5.8l1.5 2H19a1.5 1.5 0 0 1 1.5 1.5v9A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5z"/><circle cx="12" cy="12.5" r="3.6"/>', s),
  scope: (s) => svg('<circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>', s),
  sliders: (s) => svg('<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>', s),
  bolt: (s) => svg('<path d="M13 3 5.5 13.5H12L11 21l7.5-10.5H12z" fill="currentColor" stroke="none"/>', s),
  boltOff: (s) => svg('<path d="M13 3 9.6 7.8M8.2 9.9 5.5 13.5H12L11 21l3.3-4.6M16 12.3l2.5-1.8H12L13 3"/><path d="M4 4l16 16"/>', s),
  flip: (s) => svg('<path d="M4.5 9.5A8 8 0 0 1 18.4 7M19.5 14.5A8 8 0 0 1 5.6 17"/><path d="M18.8 3.6v3.8H15M5.2 20.4v-3.8H9"/><circle cx="12" cy="12" r="2.4"/>', s),
  photo: (s) => svg('<rect x="3.5" y="5" width="17" height="14" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="m4 17 4.8-4.6 3.4 3.1 2.6-2.3L20 17.6"/>', s),
  photos: (s) => svg('<rect x="6.5" y="3.5" width="14" height="11" rx="1.8"/><path d="M17.5 17.5v.5a2 2 0 0 1-2 2H5.5a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h1"/><path d="m7 12.5 3.5-3.2 2.6 2.3 2-1.7 4.4 3.3"/>', s),
  folder: (s) => svg('<path d="M3.5 7.5a2 2 0 0 1 2-2h3.8l2 2h7.2a2 2 0 0 1 2 2v7.5a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>', s),
  doc: (s) => svg('<path d="M6.5 3.5h7l4 4v11a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2z"/><path d="M13.5 3.5v4h4M8.5 12.5h7M8.5 16h5"/>', s),
  chevronRight: (s) => svg('<path d="m9.5 6 6 6-6 6"/>', s),
  chevronLeft: (s) => svg('<path d="m14.5 6-6 6 6 6"/>', s),
  check: (s) => svg('<circle cx="12" cy="12" r="8.5"/><path d="m8.4 12.2 2.4 2.4 4.8-5"/>', s),
  cross: (s) => svg('<circle cx="12" cy="12" r="8.5"/><path d="m9.3 9.3 5.4 5.4M14.7 9.3l-5.4 5.4"/>', s),
  minus: (s) => svg('<circle cx="12" cy="12" r="8.5"/><path d="M8.5 12h7"/>', s),
  alert: (s) => svg('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.8v5M12 16.2v.1"/>', s),
  share: (s) => svg('<path d="M12 3.5v11M8 7.3l4-3.8 4 3.8"/><path d="M8 10.5H6.5a1.5 1.5 0 0 0-1.5 1.5v7a1.5 1.5 0 0 0 1.5 1.5h11a1.5 1.5 0 0 0 1.5-1.5v-7a1.5 1.5 0 0 0-1.5-1.5H16"/>', s),
  download: (s) => svg('<path d="M12 3.5v11M8 10.7l4 3.8 4-3.8"/><path d="M5 16.5v2a1.5 1.5 0 0 0 1.5 1.5h11a1.5 1.5 0 0 0 1.5-1.5v-2"/>', s),
  close: (s) => svg('<path d="m6.5 6.5 11 11M17.5 6.5l-11 11"/>', s),
};
