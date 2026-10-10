import js from '@eslint/js';
import prettier from 'eslint-config-prettier';
import html from 'eslint-plugin-html';
import globals from 'globals';

export default [
  {
    ignores: [
      'node_modules/**',
      '.tools/**',
      'android/**/build/**',
      'android/app/src/main/assets/ugames/**',
      'ios/UGames/Resources/**',
      'dist/**',
    ],
  },
  {
    files: ['**/*.{js,cjs,mjs,html}'],
    plugins: { html },
    languageOptions: { ecmaVersion: 2022 },
    rules: {
      ...js.configs.recommended.rules,
      'no-unused-vars': ['error', { argsIgnorePattern: '^_', caughtErrors: 'none' }],
      'no-empty': ['error', { allowEmptyCatch: true }],
      eqeqeq: ['error', 'always', { null: 'ignore' }],
      curly: ['error', 'all'],
    },
  },
  {
    files: ['**/*.{cjs,mjs}'],
    languageOptions: { globals: globals.node },
  },
  {
    files: ['shared/**/*.js', 'shared/**/*.html'],
    languageOptions: { sourceType: 'script', globals: globals.browser },
  },
  prettier,
  { files: ['**/*.{js,cjs,mjs,html}'], rules: { curly: ['error', 'all'] } },
];
