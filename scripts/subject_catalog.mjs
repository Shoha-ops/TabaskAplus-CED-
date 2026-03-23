export const SUBJECT_CATALOG = [
  {
    code: 'AE2',
    title: 'Academic English 2',
    credits: 2,},
  {
    code: 'CAL2',
    title: 'Calculus 2',
    credits: 3,},
  {
    code: 'P2',
    title: 'Physics 2',
    credits: 3,},
  {
    code: 'OOP2',
    title: 'Object-Oriented Programming 2',
    credits: 3,},
  {
    code: 'CED',
    title: 'Creative Engineering Design',
    credits: 3,
  },
  {
    code: 'PE2',
    title: 'Physics Experiment 2',
    credits: 1,
  },
  {
    code: 'TWD',
    title: 'Technical Writing and Discussion',
    credits: 2,},
];

export const SUBJECT_BY_CODE = new Map(
  SUBJECT_CATALOG.map((item) => [item.code, item]),
);
