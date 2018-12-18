{{/*
サブシステム名を返す。
リリース名は<サブシステム名>-<環境名>なので、最後のハイフンと以降の文字列を取り除いて返す。
*/}}
{{- define "fullname" -}}
{{- .Release.Name | splitList "-" | initial | join "-" -}}
{{- end -}}
