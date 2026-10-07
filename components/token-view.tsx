type Props = {
  principal: unknown;
  idToken: { header: unknown; payload: unknown } | null;
};

// Epoch-seconds claims, shown as readable dates next to the JSON.
const TIME_CLAIMS = ["iat", "nbf", "exp", "auth_time"];

const times = (payload: unknown) =>
  TIME_CLAIMS.flatMap((k) => {
    const v = (payload as Record<string, unknown> | null)?.[k];

    return typeof v === "number" ? [`${k}: ${new Date(v * 1000).toLocaleString()}`] : [];
  });

const Json = ({ title, value }: { title: string; value: unknown }) => (
  <details className="mt-3">
    <summary className="cursor-pointer font-medium">{title}</summary>
    <pre className="mt-2 overflow-x-auto rounded-lg border border-border p-3 text-xs">
      {JSON.stringify(value, null, 2)}
    </pre>
  </details>
);

export function TokenView({ principal, idToken }: Props) {
  return (
    <div className="mt-4">
      <Json title="Client principal (X-MS-CLIENT-PRINCIPAL, decoded)" value={principal} />
      {idToken ? (
        <>
          <Json title="ID token header" value={idToken.header} />
          <Json title="ID token payload" value={idToken.payload} />
          <p className="mt-2 text-xs">{times(idToken.payload).join(" · ")}</p>
        </>
      ) : (
        <p className="mt-3 text-xs">
          No ID token header. Enable the App Service token store to see it (Authentication blade →
          Advanced → Token store).
        </p>
      )}
    </div>
  );
}
